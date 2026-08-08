import Foundation
import BerryShotIPC
#if canImport(Darwin)
import Darwin
#endif
@testable import BerryShotMCP

/// A minimal, single-purpose fake broker used only to exercise `IPCClient`
/// from the helper side of the wire, without depending on the `BerryShot`
/// GUI target (which `BerryShotMCPTests` must not import — the helper
/// itself never imports it either, per `02-target-architecture.md`
/// section 2: "It must not import the GUI executable target"). This is
/// deliberately much simpler than the real `BrokerIPCServer`: it accepts
/// connections on a background thread and answers with a
/// caller-supplied canned response, just enough to prove `IPCClient`'s
/// framing/reconnect logic against a real socket.
/// `@unchecked Sendable`: test-only fixture with the same shape as the
/// production `BrokerIPCServer` (raw fd + accept thread) for the same
/// reason — its handful of mutable properties are only ever touched from
/// `start()`/`stop()` (called synchronously from the test) or from the
/// single accept thread it owns, never concurrently.
final class FakeBrokerServer: @unchecked Sendable {
    typealias Responder = (BrokerRequest) -> BrokerResponse

    private let socketPath: String
    private var listenFD: Int32 = -1
    private var thread: Thread?
    private let respond: Responder

    init(socketPath: String, respond: @escaping Responder) {
        self.socketPath = socketPath
        self.respond = respond
    }

    /// Starts listening and returns once the socket is ready to accept.
    func start() throws {
        let parentDirectory = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FakeBrokerServerError.socketCreationFailed }
        unlink(socketPath)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw FakeBrokerServerError.pathTooLong
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
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw FakeBrokerServerError.bindFailed
        }
        guard listen(fd, 4) == 0 else {
            close(fd)
            throw FakeBrokerServerError.listenFailed
        }

        listenFD = fd
        let acceptThread = Thread { [weak self] in self?.acceptLoop() }
        acceptThread.start()
        thread = acceptThread
    }

    func stop() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    private func acceptLoop() {
        while true {
            var addr = sockaddr()
            var len = socklen_t(MemoryLayout<sockaddr>.size)
            let clientFD = accept(listenFD, &addr, &len)
            if clientFD < 0 { return }
            var one: Int32 = 1
            setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            serviceOnce(clientFD)
            close(clientFD)
        }
    }

    private func serviceOnce(_ fd: Int32) {
        var reader = IPCFrameReader()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { return }
            let chunk = Data(bytes: buffer, count: bytesRead)
            guard let frames = try? reader.feed(chunk) else { return }
            guard let payload = frames.first else { continue }
            guard let request = try? JSONDecoder().decode(BrokerRequest.self, from: payload) else { return }
            let response = respond(request)
            guard let responseData = try? JSONEncoder().encode(response) else { return }
            let frame = IPCFraming.encode(responseData)
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
            return
        }
    }
}

enum FakeBrokerServerError: Error {
    case socketCreationFailed
    case pathTooLong
    case bindFailed
    case listenFailed
}

func makeTestIPCBaseDirectory() -> URL {
    let name = "bsmcp-\(UUID().uuidString.prefix(8))"
    return URL(fileURLWithPath: "/tmp/\(name)", isDirectory: true)
}

func removeTestIPCBaseDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// Writes a `broker.json` with the given fields directly (bypassing
/// `BrokerIPCServer`, which lives in a different target) so `IPCClient`
/// tests can control exactly what the helper sees on disk.
func writeTestDescriptor(
    _ descriptor: BrokerDescriptor,
    to directory: URL,
    permissions: Int = 0o600
) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(descriptor)
    let path = directory.appendingPathComponent("broker.json").path
    FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: permissions])
}
