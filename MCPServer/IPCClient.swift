import Foundation
import Logging
import BerryShotIPC
#if canImport(Darwin)
import Darwin
#endif

/// Errors `IPCClient` throws. `BrokerErrorDTO` cases (a well-formed error
/// response the broker itself returned) are kept distinct from transport
/// failures so callers can decide how to map each into an MCP tool result.
public enum IPCClientError: Error, Sendable, Equatable {
    case descriptorUnavailable
    case descriptorInvalid(BrokerDescriptorValidation.Failure)
    case connectionFailed
    case malformedResponse
    case requestIDMismatch
    case deadlineExceeded
    case brokerError(BrokerErrorDTO)
}

/// Connects to the GUI's `BrokerIPCServer` over the private Unix-domain
/// socket named in `broker.json`, using the shared framing/DTOs from
/// `BerryShotIPC`. An `actor` so concurrent tool calls from the MCP layer
/// are naturally serialized onto one connection, matching
/// `05-mcp-server-contract.md` section 7: "FIFO capture queue... Helper
/// reconnects only a bounded number of times and never busy-polls."
///
/// This type only frames bytes, authenticates the connection, and maps
/// transport failures to typed errors. It contains no capture/redaction
/// business logic and never imports ScreenCaptureKit or Accessibility
/// (`08-implementation-work-packages.md` WP6 anti-pattern guard: "Do not
/// put capture business logic in helper").
public actor IPCClient {
    /// `nonisolated` and immutable after `init`: WP7's resource-read path
    /// (`ArtifactResourceAccess.expectedArtifactsRoot`) needs this to
    /// compute the artifact store's expected root without an `await` hop
    /// for what is, in practice, a compile-time-fixed value per process.
    public nonisolated let baseDirectory: URL
    private let maxReconnectAttempts: Int
    private let reconnectBackoffNanoseconds: UInt64
    private let log: Logger

    private var socketFD: Int32 = -1
    private var descriptor: BrokerDescriptor?

    public init(
        baseDirectory: URL = IPCClient.defaultBaseDirectory,
        maxReconnectAttempts: Int = 3,
        reconnectBackoffNanoseconds: UInt64 = 200_000_000,
        log: Logger
    ) {
        self.baseDirectory = baseDirectory
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectBackoffNanoseconds = reconnectBackoffNanoseconds
        self.log = log
    }

    public static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BerryShot", isDirectory: true)
            .appendingPathComponent("MCP", isDirectory: true)
    }

    /// Sends `operation` and returns its result, transparently reconnecting
    /// (bounded, with backoff — never busy-polling) if the current
    /// connection turns out to be dead or the descriptor is momentarily
    /// unavailable (e.g. the GUI is still starting up). `deadline` bounds
    /// both socket I/O timeouts and how long reconnect attempts are
    /// allowed to keep trying.
    ///
    /// A well-formed `BrokerErrorDTO` returned by the broker
    /// (``IPCClientError/brokerError(_:)``) is never retried: it is a
    /// deterministic response to this specific request (e.g.
    /// `invalid_argument`), not a connectivity problem, and retrying it
    /// would only add latency while producing the identical error again.
    public func send(_ operation: BrokerOperation, deadline: Date) async throws -> BrokerResult {
        var lastError: Error = IPCClientError.connectionFailed
        var attempt = 0

        while attempt <= maxReconnectAttempts {
            do {
                try ensureConnected()
                return try performRequestResponse(operation: operation, deadline: deadline)
            } catch let error as IPCClientError {
                if case .brokerError = error {
                    throw error
                }
                lastError = error
                disconnect()
                attempt += 1
                guard attempt <= maxReconnectAttempts, Date() < deadline else { break }
                log.debug("IPC connection failed; retrying", metadata: ["attempt": "\(attempt)", "error": "\(error)"])
                try? await Task.sleep(nanoseconds: reconnectBackoffNanoseconds * UInt64(attempt))
            } catch {
                lastError = error
                disconnect()
                attempt += 1
                guard attempt <= maxReconnectAttempts, Date() < deadline else { break }
                log.debug("IPC connection failed; retrying", metadata: ["attempt": "\(attempt)", "error": "\(error)"])
                try? await Task.sleep(nanoseconds: reconnectBackoffNanoseconds * UInt64(attempt))
            }
        }
        throw lastError
    }

    /// Closes the current connection, if any, so the next `send` reconnects
    /// from scratch (fresh descriptor read, fresh socket).
    public func disconnect() {
        if socketFD >= 0 {
            close(socketFD)
        }
        socketFD = -1
    }

    // MARK: - Connection

    private func ensureConnected() throws {
        guard socketFD < 0 else { return }

        let loadedDescriptor: BrokerDescriptor
        do {
            loadedDescriptor = try BrokerDescriptorLoader.load(from: baseDirectory)
        } catch let error as BrokerDescriptorLoader.LoadError {
            switch error {
            case .descriptorUnavailable, .descriptorUnreadable:
                throw IPCClientError.descriptorUnavailable
            case .invalid(let failure):
                throw IPCClientError.descriptorInvalid(failure)
            }
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCClientError.connectionFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(loadedDescriptor.socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw IPCClientError.connectionFailed
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let buffer = raw.bindMemory(to: UInt8.self)
            for (index, byte) in pathBytes.enumerated() { buffer[index] = byte }
            buffer[pathBytes.count] = 0
        }
        #if canImport(Darwin)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }
        guard connectResult == 0 else {
            close(fd)
            throw IPCClientError.connectionFailed
        }

        // A peer that already closed its end must fail our write() with
        // EPIPE, not raise SIGPIPE and kill this helper process.
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        socketFD = fd
        descriptor = loadedDescriptor
    }

    private func performRequestResponse(operation: BrokerOperation, deadline: Date) throws -> BrokerResult {
        guard let descriptor else { throw IPCClientError.connectionFailed }

        applySocketTimeout(deadline: deadline)

        let requestID = UUID()
        let request = BrokerRequest(requestID: requestID, deadline: deadline, sessionToken: descriptor.sessionToken, operation: operation)
        let payload = try JSONEncoder().encode(request)
        guard writeAll(IPCFraming.encode(payload)) else {
            throw IPCClientError.connectionFailed
        }

        guard let responseData = readOneFrame() else {
            throw IPCClientError.connectionFailed
        }
        guard let response = try? JSONDecoder().decode(BrokerResponse.self, from: responseData) else {
            throw IPCClientError.malformedResponse
        }
        guard response.requestID == requestID else {
            throw IPCClientError.requestIDMismatch
        }
        if let error = response.error {
            throw IPCClientError.brokerError(error)
        }
        guard let result = response.result else {
            throw IPCClientError.malformedResponse
        }
        return result
    }

    private func applySocketTimeout(deadline: Date) {
        let remaining = max(0.1, deadline.timeIntervalSinceNow)
        var timeout = timeval(tv_sec: Int(remaining), tv_usec: Int32((remaining - Double(Int(remaining))) * 1_000_000))
        setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func writeAll(_ data: Data) -> Bool {
        data.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return true }
            var offset = 0
            while offset < ptr.count {
                let written = write(socketFD, base.advanced(by: offset), ptr.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }

    private func readOneFrame() -> Data? {
        var reader = IPCFrameReader()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let bytesRead = read(socketFD, &buffer, buffer.count)
            if bytesRead <= 0 { return nil }
            let chunk = Data(bytes: buffer, count: bytesRead)
            guard let frames = try? reader.feed(chunk) else { return nil }
            if let first = frames.first { return first }
        }
    }
}
