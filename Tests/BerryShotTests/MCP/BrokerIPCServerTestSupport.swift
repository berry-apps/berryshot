import Foundation
import BerryShotIPC
#if canImport(Darwin)
import Darwin
#endif
@testable import BerryShot

/// A raw Unix-domain socket test client used only to exercise
/// `BrokerIPCServer`'s wire protocol directly (framing, auth, deadlines)
/// without depending on the `BerryShotMCP` helper target, which is built
/// and tested separately (`IPCClient` in `BerryShotMCPTests`).
enum TestIPCClient {
    /// This test harness is the one place in the codebase where a
    /// Unix-domain socket "client" and the real `BrokerIPCServer` under
    /// test share a single process's file-descriptor table — production
    /// `BerryShotMCP` and `BerryShot.app` never do, since they're always
    /// separate OS processes with independent fd tables. That sharing
    /// makes this specific test setup susceptible to fd-number reuse races
    /// under `dispatch_apply`-driven concurrent connect/send/close cycles
    /// (verified via `lldb` catching a live `SIGPIPE` inside a concurrent
    /// iteration's `readOneFrame`, spawned from
    /// `testConcurrentConnectionsIncludingSomeRejectedPeersDoNotCorruptState`),
    /// even though every individual fd here already carries `SO_NOSIGPIPE`.
    /// A `SIGPIPE` should never be allowed to kill the whole test process;
    /// ignore it process-wide once, the same way `HelperStdoutProtocolTests`
    /// and `MCPServer/main.swift` already do for their own writers.
    private static let sigpipeIgnored: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    static func connect(path: String) -> Int32? {
        _ = sigpipeIgnored
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            return nil
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
        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }

        // Fail fast instead of hanging the test suite if the server never
        // responds.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        // Several tests deliberately write to a socket the server has
        // already closed its end of (rejected peer, malformed frame); avoid
        // SIGPIPE killing the whole test process the same way production
        // code must (see BrokerIPCServer.acceptConnection).
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    static func send(_ payload: Data, on fd: Int32) {
        let frame = IPCFraming.encode(payload)
        _ = frame.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return true }
            var offset = 0
            while offset < ptr.count {
                let written = write(fd, base.advanced(by: offset), ptr.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }

    /// Sends a raw, already-framed byte sequence verbatim (used to send a
    /// length prefix that lies about a payload the client never actually
    /// follows up with, exercising the over-limit-frame path).
    static func sendRaw(_ data: Data, on fd: Int32) {
        _ = data.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return true }
            var offset = 0
            while offset < ptr.count {
                let written = write(fd, base.advanced(by: offset), ptr.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }

    /// Reads until one complete frame has arrived, or `nil` on EOF/timeout/error.
    static func readOneFrame(from fd: Int32) -> Data? {
        var reader = IPCFrameReader()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { return nil }
            let chunk = Data(bytes: buffer, count: bytesRead)
            guard let frames = try? reader.feed(chunk) else { return nil }
            if let first = frames.first { return first }
        }
    }

    /// Reads raw bytes (not frame-decoded) with a short deadline, used only
    /// to assert that *nothing at all* comes back (e.g. after a rejected
    /// peer or a malformed request the server intentionally just closes).
    static func expectNoDataOrEOF(from fd: Int32) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 16)
        let bytesRead = read(fd, &buffer, buffer.count)
        return bytesRead <= 0
    }
}

/// Creates a short, guaranteed-under-104-byte directory path for
/// `BrokerIPCServer`'s socket + descriptor files. `NSTemporaryDirectory()`
/// on some machines is long enough that `/…/T/BerryShot/MCP/broker.sock`
/// would overflow `sockaddr_un.sun_path`, so tests use `/tmp` directly
/// (itself typically a symlink to a short path) with a short random suffix.
func makeTestBrokerBaseDirectory() -> URL {
    let name = "bsipc-\(UUID().uuidString.prefix(8))"
    let url = URL(fileURLWithPath: "/tmp/\(name)", isDirectory: true)
    return url
}

func removeTestBrokerBaseDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

struct FakePeerCredentialLookup: PeerCredentialLookup {
    let uid: UInt32?
    func peerUID(forFileDescriptor fileDescriptor: Int32) -> UInt32? { uid }
}

func makeTestBroker() -> CaptureBroker {
    CaptureBroker(discovery: EmptyDiscovery(), permissions: FixedPermissions())
}

struct EmptyDiscovery: CaptureBrokerDiscovering {
    func discoverApplications() async throws -> [ApplicationDescriptor] { [] }
    func discoverWindows() async throws -> [WindowDescriptor] { [] }
}

struct FixedPermissions: CaptureBrokerPermissionsChecking {
    func screenCaptureGranted() -> Bool { true }
    func accessibilityGranted() -> Bool { true }
}
