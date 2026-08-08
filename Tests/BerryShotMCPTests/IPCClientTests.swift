import XCTest
import Logging
import BerryShotIPC
@testable import BerryShotMCP

final class IPCClientTests: XCTestCase {
    private var baseDirectory: URL!
    private var fakeServer: FakeBrokerServer?

    override func setUp() {
        super.setUp()
        baseDirectory = makeTestIPCBaseDirectory()
    }

    override func tearDown() {
        fakeServer?.stop()
        fakeServer = nil
        removeTestIPCBaseDirectory(baseDirectory)
        baseDirectory = nil
        super.tearDown()
    }

    private func makeClient(maxReconnectAttempts: Int = 3) -> IPCClient {
        IPCClient(baseDirectory: baseDirectory, maxReconnectAttempts: maxReconnectAttempts, reconnectBackoffNanoseconds: 100_000_000, log: Logger(label: "test"))
    }

    // MARK: - Descriptor errors

    func testSendFailsWithDescriptorUnavailableWhenNoDescriptorFileExists() async throws {
        let client = makeClient()
        do {
            _ = try await client.send(.ping, deadline: Date().addingTimeInterval(5))
            XCTFail("Expected descriptorUnavailable")
        } catch let error as IPCClientError {
            XCTAssertEqual(error, .descriptorUnavailable)
        }
    }

    func testSendFailsWithDescriptorInvalidWhenFileIsGroupReadable() async throws {
        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: baseDirectory.appendingPathComponent("broker.sock").path,
            guiPID: ProcessInfo.processInfo.processIdentifier,
            expiresAt: Date().addingTimeInterval(3600),
            sessionToken: "irrelevant"
        )
        try writeTestDescriptor(descriptor, to: baseDirectory, permissions: 0o640)

        let client = makeClient()
        do {
            _ = try await client.send(.ping, deadline: Date().addingTimeInterval(5))
            XCTFail("Expected descriptorInvalid")
        } catch let error as IPCClientError {
            XCTAssertEqual(error, .descriptorInvalid(.groupOrOtherPermissionBitsSet))
        }
    }

    func testSendFailsWithDescriptorInvalidWhenExpired() async throws {
        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: baseDirectory.appendingPathComponent("broker.sock").path,
            guiPID: ProcessInfo.processInfo.processIdentifier,
            expiresAt: Date().addingTimeInterval(-10),
            sessionToken: "irrelevant"
        )
        try writeTestDescriptor(descriptor, to: baseDirectory)

        let client = makeClient()
        do {
            _ = try await client.send(.ping, deadline: Date().addingTimeInterval(5))
            XCTFail("Expected descriptorInvalid")
        } catch let error as IPCClientError {
            XCTAssertEqual(error, .descriptorInvalid(.expired))
        }
    }

    func testSendFailsWithDescriptorInvalidWhenGUIProcessIsNotAlive() async throws {
        // PID 999999 is extremely unlikely to be a live process.
        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: baseDirectory.appendingPathComponent("broker.sock").path,
            guiPID: 999_999,
            expiresAt: Date().addingTimeInterval(3600),
            sessionToken: "irrelevant"
        )
        try writeTestDescriptor(descriptor, to: baseDirectory)

        let client = makeClient()
        do {
            _ = try await client.send(.ping, deadline: Date().addingTimeInterval(5))
            XCTFail("Expected descriptorInvalid")
        } catch let error as IPCClientError {
            XCTAssertEqual(error, .descriptorInvalid(.processNotAlive))
        }
    }

    // MARK: - Happy path against a fake broker

    func testSendSucceedsAgainstAFakeBrokerServer() async throws {
        let socketPath = baseDirectory.appendingPathComponent("broker.sock").path
        let server = FakeBrokerServer(socketPath: socketPath) { request in
            .success(requestID: request.requestID, result: .pong)
        }
        try server.start()
        fakeServer = server

        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: socketPath,
            guiPID: ProcessInfo.processInfo.processIdentifier,
            expiresAt: Date().addingTimeInterval(3600),
            sessionToken: "correct-token"
        )
        try writeTestDescriptor(descriptor, to: baseDirectory)

        let client = makeClient()
        let result = try await client.send(.ping, deadline: Date().addingTimeInterval(5))
        XCTAssertEqual(result, .pong)
    }

    func testSendSurfacesBrokerReturnedErrorAsBrokerError() async throws {
        let socketPath = baseDirectory.appendingPathComponent("broker.sock").path
        let server = FakeBrokerServer(socketPath: socketPath) { request in
            .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .rateLimited, message: "Too many pending requests"))
        }
        try server.start()
        fakeServer = server

        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: socketPath,
            guiPID: ProcessInfo.processInfo.processIdentifier,
            expiresAt: Date().addingTimeInterval(3600),
            sessionToken: "correct-token"
        )
        try writeTestDescriptor(descriptor, to: baseDirectory)

        let client = makeClient()
        do {
            _ = try await client.send(.ping, deadline: Date().addingTimeInterval(5))
            XCTFail("Expected brokerError")
        } catch let error as IPCClientError {
            XCTAssertEqual(error, .brokerError(BrokerErrorDTO(code: .rateLimited, message: "Too many pending requests")))
        }
    }

    func testMismatchedResponseRequestIDIsRejected() async throws {
        let socketPath = baseDirectory.appendingPathComponent("broker.sock").path
        let server = FakeBrokerServer(socketPath: socketPath) { _ in
            .success(requestID: UUID(), result: .pong) // deliberately wrong ID
        }
        try server.start()
        fakeServer = server

        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: socketPath,
            guiPID: ProcessInfo.processInfo.processIdentifier,
            expiresAt: Date().addingTimeInterval(3600),
            sessionToken: "correct-token"
        )
        try writeTestDescriptor(descriptor, to: baseDirectory)

        let client = makeClient()
        do {
            _ = try await client.send(.ping, deadline: Date().addingTimeInterval(5))
            XCTFail("Expected requestIDMismatch")
        } catch let error as IPCClientError {
            XCTAssertEqual(error, .requestIDMismatch)
        }
    }

    // MARK: - Reconnect

    func testReconnectGivesUpAfterBoundedAttemptsWithoutHangingOrBusyPolling() async throws {
        // A descriptor pointing at a socket path nothing is listening on;
        // every connect() attempt fails immediately (ECONNREFUSED/ENOENT),
        // so this measures only the bounded backoff between attempts, not
        // any socket-level read timeout.
        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: baseDirectory.appendingPathComponent("broker.sock").path,
            guiPID: ProcessInfo.processInfo.processIdentifier,
            expiresAt: Date().addingTimeInterval(3600),
            sessionToken: "irrelevant"
        )
        try writeTestDescriptor(descriptor, to: baseDirectory)

        let client = makeClient(maxReconnectAttempts: 3)
        let start = Date()
        do {
            _ = try await client.send(.ping, deadline: Date().addingTimeInterval(10))
            XCTFail("Expected connectionFailed")
        } catch let error as IPCClientError {
            XCTAssertEqual(error, .connectionFailed)
        }
        let elapsed = Date().timeIntervalSince(start)
        // Backoff is 100ms * attempt for attempts 1...3 = 0.6s of sleeping;
        // bounded well under the 10s deadline, and comfortably more than
        // "instant" (which would indicate no backoff/busy-polling).
        XCTAssertGreaterThan(elapsed, 0.2)
        XCTAssertLessThan(elapsed, 3.0)
    }

    func testReconnectSucceedsOnceTheBrokerBecomesAvailableDuringBackoff() async throws {
        let socketPath = baseDirectory.appendingPathComponent("broker.sock").path
        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: socketPath,
            guiPID: ProcessInfo.processInfo.processIdentifier,
            expiresAt: Date().addingTimeInterval(3600),
            sessionToken: "correct-token"
        )
        try writeTestDescriptor(descriptor, to: baseDirectory)
        // Deliberately do not start the fake server yet.

        let client = makeClient(maxReconnectAttempts: 5)
        let sendTask = Task {
            try await client.send(.ping, deadline: Date().addingTimeInterval(10))
        }

        // Start the broker mid-flight, after the client has almost
        // certainly already failed its first connect attempt.
        try await Task.sleep(nanoseconds: 150_000_000)
        let server = FakeBrokerServer(socketPath: socketPath) { request in
            .success(requestID: request.requestID, result: .pong)
        }
        try server.start()
        fakeServer = server

        let result = try await sendTask.value
        XCTAssertEqual(result, .pong)
    }

    func testDisconnectForcesFreshConnectionOnNextSend() async throws {
        let socketPath = baseDirectory.appendingPathComponent("broker.sock").path
        let server = FakeBrokerServer(socketPath: socketPath) { request in
            .success(requestID: request.requestID, result: .pong)
        }
        try server.start()
        fakeServer = server

        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: socketPath,
            guiPID: ProcessInfo.processInfo.processIdentifier,
            expiresAt: Date().addingTimeInterval(3600),
            sessionToken: "correct-token"
        )
        try writeTestDescriptor(descriptor, to: baseDirectory)

        let client = makeClient()
        let first = try await client.send(.ping, deadline: Date().addingTimeInterval(5))
        XCTAssertEqual(first, .pong)

        await client.disconnect()

        let second = try await client.send(.ping, deadline: Date().addingTimeInterval(5))
        XCTAssertEqual(second, .pong)
    }
}
