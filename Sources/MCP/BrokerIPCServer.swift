import Foundation
import BerryShotIPC
import os
#if canImport(Darwin)
import Darwin
#endif

private let ipcLog = Logger(subsystem: "com.tan.berryshot", category: "MCPBroker")

/// Errors surfaced to the Privacy settings UI when the broker fails to
/// start. Never shown with raw `errno`/path detail beyond what a user
/// toggling a checkbox needs; callers log the associated value themselves
/// if they want detail in Console.app.
public enum BrokerIPCServerError: Error, Sendable, Equatable {
    case alreadyRunning
    case socketDirectoryUnavailable
    case socketPathTooLong
    case socketCreationFailed(errno: Int32)
    case socketBindFailed(errno: Int32)
    case socketListenFailed(errno: Int32)
    case descriptorWriteFailed
}

/// Looks up the credentials of the peer connected to a Unix-domain socket
/// file descriptor. A protocol (rather than a free function) so
/// `BrokerIPCServer` can be constructed in a test with a fake that reports
/// an arbitrary UID without needing a real second macOS user account — this
/// is the "peer rejection seam" required by
/// `08-implementation-work-packages.md` WP6 task 8. The real syscall path
/// (`LivePeerCredentialLookup`) is still exercised end-to-end by every
/// other `BrokerIPCServer` integration test that connects a real client
/// socket, since a same-process test client always presents same-UID
/// credentials.
public protocol PeerCredentialLookup: Sendable {
    /// Returns the effective UID of the process on the other end of
    /// `fileDescriptor`, or `nil` if credentials could not be determined
    /// (treated as untrusted).
    func peerUID(forFileDescriptor fileDescriptor: Int32) -> UInt32?
}

public struct LivePeerCredentialLookup: PeerCredentialLookup {
    public init() {}

    public func peerUID(forFileDescriptor fileDescriptor: Int32) -> UInt32? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fileDescriptor, &uid, &gid) == 0 else { return nil }
        return UInt32(uid)
    }
}

/// Pure decision function isolated from the syscall above so it has its own
/// direct unit test independent of any socket.
enum PeerAuthorization {
    static func isAuthorized(peerUID: UInt32?, expectedUID: UInt32) -> Bool {
        guard let peerUID else { return false }
        return peerUID == expectedUID
    }
}

/// Private, same-user Unix-domain IPC server described in
/// `05-mcp-server-contract.md` section 7. Owns the listening socket, the
/// `broker.json` descriptor file, and per-connection framing/authentication.
/// All business logic (what an operation actually does) lives in
/// `CaptureBroker`; this type only authenticates peers, frames bytes, and
/// dispatches to the broker.
///
/// Never started automatically: nothing in `AppDelegate`/app startup
/// constructs or starts this type. It is only created and `start()`-ed from
/// the Privacy setting's explicit opt-in toggle
/// (`MCPIntegrationSettings`), matching
/// `08-implementation-work-packages.md` WP6 verification: "No always-running
/// helper process."
///
/// `@unchecked Sendable`: this type owns raw POSIX socket file descriptors
/// and spawns one background `Thread` per connection to perform blocking
/// `read`/`write`, which the compiler cannot reason about for `Sendable`.
/// Every mutable property below is only ever touched while holding
/// `stateLock`; there is no path that mutates state outside that lock. See
/// `BrokerIPCServerConcurrencyTests` for a stress test that opens many
/// concurrent connections and asserts no crash/corruption, and
/// `BrokerIPCServerTests` for the single-connection protocol behavior.
public final class BrokerIPCServer: @unchecked Sendable {
    private let broker: CaptureBroker
    private let baseDirectoryURL: URL
    private let peerCredentialLookup: any PeerCredentialLookup
    private let ownerUID: UInt32

    private let stateLock = NSLock()
    private var isRunning = false
    private var listenSocketFD: Int32 = -1
    private var acceptThread: Thread?
    private var activeConnections: Set<ConnectionHandle> = []
    private var currentSessionToken: String?
    private var socketPathOnDisk: String?
    private var descriptorPathOnDisk: URL?

    public init(
        broker: CaptureBroker,
        baseDirectory: URL = BrokerIPCServer.defaultBaseDirectory,
        peerCredentialLookup: any PeerCredentialLookup = LivePeerCredentialLookup(),
        ownerUID: UInt32 = UInt32(getuid())
    ) {
        self.broker = broker
        self.baseDirectoryURL = baseDirectory
        self.peerCredentialLookup = peerCredentialLookup
        self.ownerUID = ownerUID
    }

    public static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BerryShot", isDirectory: true)
            .appendingPathComponent("MCP", isDirectory: true)
    }

    public var isRunningNow: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return isRunning
    }

    /// Starts listening and publishes a freshly rotated `broker.json`
    /// descriptor. Idempotent-unsafe by design: calling `start()` while
    /// already running throws `.alreadyRunning` rather than silently
    /// reusing or leaking the previous socket.
    @discardableResult
    public func start() throws -> BrokerDescriptor {
        stateLock.lock()
        guard !isRunning else {
            stateLock.unlock()
            throw BrokerIPCServerError.alreadyRunning
        }
        stateLock.unlock()

        try createBaseDirectoryIfNeeded()
        let socketPath = baseDirectoryURL.appendingPathComponent("broker.sock").path
        let listenFD = try createListenSocket(atPath: socketPath)

        let token = Self.generateSessionToken()
        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: socketPath,
            guiPID: ProcessInfo.processInfo.processIdentifier,
            expiresAt: Date().addingTimeInterval(IPCProtocol.descriptorLifetime),
            sessionToken: token
        )
        let descriptorURL = baseDirectoryURL.appendingPathComponent("broker.json")
        do {
            try writeDescriptorAtomically(descriptor, to: descriptorURL)
        } catch {
            close(listenFD)
            unlink(socketPath)
            throw BrokerIPCServerError.descriptorWriteFailed
        }

        stateLock.lock()
        isRunning = true
        listenSocketFD = listenFD
        currentSessionToken = token
        socketPathOnDisk = socketPath
        descriptorPathOnDisk = descriptorURL
        stateLock.unlock()

        let thread = Thread { [weak self] in
            self?.runAcceptLoop(listenFD: listenFD)
        }
        thread.name = "com.tan.berryshot.mcp.accept"
        thread.start()
        stateLock.lock()
        acceptThread = thread
        stateLock.unlock()

        ipcLog.info("MCP broker started")
        return descriptor
    }

    /// Stops listening, closes every active connection, cancels the
    /// broker's queue, and removes the socket/descriptor files. Safe to
    /// call when not running.
    public func stop() {
        stateLock.lock()
        guard isRunning else {
            stateLock.unlock()
            return
        }
        isRunning = false
        let fd = listenSocketFD
        listenSocketFD = -1
        let connections = activeConnections
        activeConnections.removeAll()
        let socketPath = socketPathOnDisk
        let descriptorPath = descriptorPathOnDisk
        socketPathOnDisk = nil
        descriptorPathOnDisk = nil
        currentSessionToken = nil
        stateLock.unlock()

        if fd >= 0 {
            close(fd) // interrupts the blocking accept() loop
        }
        for connection in connections {
            shutdown(connection.fd, SHUT_RDWR) // interrupts any blocking read()/write()
            close(connection.fd)
        }
        if let socketPath { unlink(socketPath) }
        if let descriptorPath { try? FileManager.default.removeItem(at: descriptorPath) }

        Task { await broker.cancelAll() }
        ipcLog.info("MCP broker stopped")
    }

    // MARK: - Socket setup

    private func createBaseDirectoryIfNeeded() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDirectoryURL.path)
        } catch {
            throw BrokerIPCServerError.socketDirectoryUnavailable
        }
    }

    private func createListenSocket(atPath path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BrokerIPCServerError.socketCreationFailed(errno: errno) }

        // Remove a stale socket file left behind by a crashed previous run.
        unlink(path)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else {
            close(fd)
            throw BrokerIPCServerError.socketPathTooLong
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            let buffer = rawPtr.bindMemory(to: UInt8.self)
            for (index, byte) in pathBytes.enumerated() { buffer[index] = byte }
            buffer[pathBytes.count] = 0
        }
        #if canImport(Darwin)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            let bindErrno = errno
            close(fd)
            throw BrokerIPCServerError.socketBindFailed(errno: bindErrno)
        }

        // Belt-and-suspenders: the containing directory is already 0700,
        // but explicitly pin the socket file mode too regardless of umask.
        chmod(path, 0o600)

        guard listen(fd, 16) == 0 else {
            let listenErrno = errno
            close(fd)
            throw BrokerIPCServerError.socketListenFailed(errno: listenErrno)
        }
        return fd
    }

    private static func generateSessionToken() -> String {
        var bytes = [UInt8](repeating: 0, count: IPCProtocol.sessionTokenByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes must succeed to establish a broker session")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func writeDescriptorAtomically(_ descriptor: BrokerDescriptor, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(descriptor)

        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".broker-\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)

        let renameResult = tempURL.path.withCString { tempPath in
            url.path.withCString { finalPath in
                rename(tempPath, finalPath)
            }
        }
        guard renameResult == 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw BrokerIPCServerError.descriptorWriteFailed
        }
    }

    // MARK: - Accept loop

    private func runAcceptLoop(listenFD: Int32) {
        while true {
            var clientAddr = sockaddr()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr>.size)
            let clientFD = accept(listenFD, &clientAddr, &clientAddrLen)
            if clientFD < 0 {
                if errno == EINTR { continue }
                // Listening socket was closed by stop(); exit the loop.
                return
            }
            guard isRunningNow else {
                close(clientFD)
                return
            }
            acceptConnection(clientFD)
        }
    }

    private func acceptConnection(_ fd: Int32) {
        // Without this, `write()` (in `writeAll`, below) raises `SIGPIPE`
        // when the peer has already closed its end — e.g. a helper that
        // disconnects mid-request — and `SIGPIPE`'s default disposition
        // terminates the whole process. That would mean a misbehaving or
        // merely-impatient MCP helper could kill the entire BerryShot GUI.
        // `SO_NOSIGPIPE` makes a closed-peer write fail with `EPIPE`
        // (handled as a normal write failure in `writeAll`) instead.
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        let peerUID = peerCredentialLookup.peerUID(forFileDescriptor: fd)
        guard PeerAuthorization.isAuthorized(peerUID: peerUID, expectedUID: ownerUID) else {
            ipcLog.notice("Rejected IPC connection from a different user or unreadable peer credentials")
            close(fd)
            return
        }

        let handle = ConnectionHandle(fd: fd)
        stateLock.lock()
        activeConnections.insert(handle)
        stateLock.unlock()

        let thread = Thread { [weak self] in
            self?.serviceConnection(handle)
            self?.stateLock.lock()
            self?.activeConnections.remove(handle)
            self?.stateLock.unlock()
        }
        thread.name = "com.tan.berryshot.mcp.connection"
        thread.start()
    }

    // MARK: - Per-connection framing/auth/dispatch

    private func serviceConnection(_ handle: ConnectionHandle) {
        var reader = IPCFrameReader()
        var readBuffer = [UInt8](repeating: 0, count: 64 * 1024)
        var inFlightRequestIDs: Set<UUID> = []

        defer {
            close(handle.fd)
            for requestID in inFlightRequestIDs {
                Task { await broker.cancel(requestID: requestID) }
            }
        }

        while true {
            let bytesRead = readBuffer.withUnsafeMutableBytes { ptr -> Int in
                read(handle.fd, ptr.baseAddress, ptr.count)
            }
            if bytesRead <= 0 { return } // 0 = peer closed; <0 = error

            let chunk = Data(bytes: readBuffer, count: bytesRead)
            let frames: [Data]
            do {
                frames = try reader.feed(chunk)
            } catch {
                ipcLog.notice("Closing IPC connection after an over-limit frame")
                return
            }

            for payload in frames {
                let (responseData, requestID) = process(payload: payload, inFlight: &inFlightRequestIDs)
                let framed = IPCFraming.encode(responseData)
                if !writeAll(framed, to: handle.fd) {
                    return // peer gone; defer{} above will cancel any leftover in-flight IDs
                }
                if let requestID {
                    inFlightRequestIDs.remove(requestID)
                }
            }
        }
    }

    /// Decodes and dispatches one request frame, returning the encoded
    /// response and (when known) the request ID that finished so the
    /// caller can stop tracking it as in-flight.
    private func process(payload: Data, inFlight: inout Set<UUID>) -> (Data, UUID?) {
        let decoder = JSONDecoder()
        guard let request = try? decoder.decode(BrokerRequest.self, from: payload) else {
            let response = BrokerResponse.failure(
                requestID: BrokerResponse.unknownRequestID,
                error: BrokerErrorDTO(code: .malformedRequest, message: "Malformed request")
            )
            return (encodeOrEmpty(response), nil)
        }

        inFlight.insert(request.requestID)
        let response = validateAndDispatch(request)
        return (encodeOrEmpty(response), request.requestID)
    }

    private func encodeOrEmpty(_ response: BrokerResponse) -> Data {
        (try? JSONEncoder().encode(response)) ?? Data()
    }

    private func validateAndDispatch(_ request: BrokerRequest) -> BrokerResponse {
        guard request.protocolVersion == IPCProtocol.currentVersion else {
            return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .protocolVersionMismatch, message: "Unsupported protocol version"))
        }

        stateLock.lock()
        let expectedToken = currentSessionToken
        stateLock.unlock()

        guard let expectedToken, Self.constantTimeEquals(request.sessionToken, expectedToken) else {
            return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .unauthorized, message: "Invalid session token"))
        }
        guard request.deadline > Date() else {
            return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .deadlineExceeded, message: "Deadline already passed"))
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResponseBox(.failure(requestID: request.requestID, error: BrokerErrorDTO(code: .internalError, message: "Internal error")))
        Task { [broker] in
            do {
                let result = try await broker.submit(request.operation, requestID: request.requestID, deadline: request.deadline)
                box.response = .success(requestID: request.requestID, result: result)
            } catch let error as BrokerOperationError {
                box.response = .failure(requestID: request.requestID, error: error.dto)
            } catch {
                box.response = .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .internalError, message: "Internal error"))
            }
            semaphore.signal()
        }
        semaphore.wait()
        return box.response
    }

    /// Length-then-byte-XOR comparison. Token length itself is not secret
    /// (it is a fixed, publicly-known constant), so the early-return on a
    /// length mismatch does not leak anything an attacker doesn't already
    /// know; every byte of an equal-length candidate is still compared
    /// without short-circuiting.
    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else { return false }
        var diff: UInt8 = 0
        for index in 0..<lhsBytes.count {
            diff |= lhsBytes[index] ^ rhsBytes[index]
        }
        return diff == 0
    }

    private func writeAll(_ data: Data, to fd: Int32) -> Bool {
        var offset = 0
        let count = data.count
        return data.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return count == 0 }
            while offset < count {
                let written = write(fd, base.advanced(by: offset), count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }
}

private struct ConnectionHandle: Hashable {
    let fd: Int32
}

/// Bridges one async `CaptureBroker.submit` call back to the blocking
/// per-connection `Thread` that is waiting on `semaphore.wait()` in
/// `validateAndDispatch(_:)`.
///
/// `@unchecked Sendable` is safe here specifically because of that
/// semaphore, even though the compiler cannot see it: the `Task` writes
/// `response` exactly once and only calls `semaphore.signal()` after that
/// write completes; the blocking thread only reads `response` after
/// `semaphore.wait()` returns, which cannot happen before the matching
/// `signal()`. There is therefore no concurrent access to `response` in
/// practice, only a compiler-invisible happens-before edge through the
/// semaphore.
private final class ResponseBox: @unchecked Sendable {
    var response: BrokerResponse
    init(_ response: BrokerResponse) {
        self.response = response
    }
}
