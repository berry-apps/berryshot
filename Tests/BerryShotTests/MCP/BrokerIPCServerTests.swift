import XCTest
import BerryShotIPC
#if canImport(Darwin)
import Darwin
#endif
@testable import BerryShot

final class BrokerIPCServerTests: XCTestCase {
    private var baseDirectory: URL!
    private var server: BrokerIPCServer!

    override func setUp() {
        super.setUp()
        baseDirectory = makeTestBrokerBaseDirectory()
    }

    override func tearDown() {
        server?.stop()
        server = nil
        removeTestBrokerBaseDirectory(baseDirectory)
        baseDirectory = nil
        super.tearDown()
    }

    private func startServer(peerCredentialLookup: any PeerCredentialLookup = LivePeerCredentialLookup()) throws -> BrokerDescriptor {
        server = BrokerIPCServer(broker: makeTestBroker(), baseDirectory: baseDirectory, peerCredentialLookup: peerCredentialLookup)
        return try server.start()
    }

    private func decodeResponse(_ data: Data) throws -> BrokerResponse {
        try JSONDecoder().decode(BrokerResponse.self, from: data)
    }

    // MARK: - Directory/socket/descriptor permissions

    func testStartCreatesDirectoryWithOwnerOnlyPermissions() throws {
        _ = try startServer()
        var attributes: [FileAttributeKey: Any]?
        attributes = try? FileManager.default.attributesOfItem(atPath: baseDirectory.path)
        let posix = attributes?[.posixPermissions] as? NSNumber
        XCTAssertEqual(posix?.intValue, 0o700)
    }

    func testStartWritesDescriptorWithOwnerOnlyFileMode() throws {
        _ = try startServer()
        let descriptorPath = baseDirectory.appendingPathComponent("broker.json").path
        let attributes = try FileManager.default.attributesOfItem(atPath: descriptorPath)
        let posix = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(posix?.intValue, 0o600)
    }

    func testDescriptorContainsExpectedFields() throws {
        let descriptor = try startServer()
        XCTAssertEqual(descriptor.protocolVersion, IPCProtocol.currentVersion)
        XCTAssertEqual(descriptor.guiPID, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(descriptor.socketPath, baseDirectory.appendingPathComponent("broker.sock").path)
        XCTAssertGreaterThan(descriptor.expiresAt, Date())
        XCTAssertFalse(descriptor.sessionToken.isEmpty)
    }

    func testStartingTwiceThrowsAlreadyRunning() throws {
        _ = try startServer()
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? BrokerIPCServerError, .alreadyRunning)
        }
    }

    // MARK: - Happy path

    func testPingWithValidTokenAndVersionSucceeds() throws {
        let descriptor = try startServer()
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(fd) }

        let requestID = UUID()
        let request = BrokerRequest(requestID: requestID, deadline: Date().addingTimeInterval(30), sessionToken: descriptor.sessionToken, operation: .ping)
        TestIPCClient.send(try JSONEncoder().encode(request), on: fd)

        let responseData = try XCTUnwrap(TestIPCClient.readOneFrame(from: fd))
        let response = try decodeResponse(responseData)
        XCTAssertEqual(response.requestID, requestID)
        XCTAssertEqual(response.result, .pong)
        XCTAssertNil(response.error)
    }

    func testMultipleRequestsOverTheSameConnectionAreEachAnswered() throws {
        let descriptor = try startServer()
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(fd) }

        for _ in 0..<5 {
            let requestID = UUID()
            let request = BrokerRequest(requestID: requestID, deadline: Date().addingTimeInterval(30), sessionToken: descriptor.sessionToken, operation: .ping)
            TestIPCClient.send(try JSONEncoder().encode(request), on: fd)
            let responseData = try XCTUnwrap(TestIPCClient.readOneFrame(from: fd))
            let response = try decodeResponse(responseData)
            XCTAssertEqual(response.requestID, requestID)
            XCTAssertEqual(response.result, .pong)
        }
    }

    // MARK: - Bad token / version / deadline

    func testWrongSessionTokenIsRejectedWithUnauthorized() throws {
        let descriptor = try startServer()
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(fd) }

        let request = BrokerRequest(deadline: Date().addingTimeInterval(30), sessionToken: "not-the-real-token", operation: .ping)
        TestIPCClient.send(try JSONEncoder().encode(request), on: fd)

        let responseData = try XCTUnwrap(TestIPCClient.readOneFrame(from: fd))
        let response = try decodeResponse(responseData)
        XCTAssertNil(response.result)
        XCTAssertEqual(response.error?.code, .unauthorized)
    }

    func testWrongProtocolVersionIsRejected() throws {
        let descriptor = try startServer()
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(fd) }

        let request = BrokerRequest(protocolVersion: 999, deadline: Date().addingTimeInterval(30), sessionToken: descriptor.sessionToken, operation: .ping)
        TestIPCClient.send(try JSONEncoder().encode(request), on: fd)

        let responseData = try XCTUnwrap(TestIPCClient.readOneFrame(from: fd))
        let response = try decodeResponse(responseData)
        XCTAssertNil(response.result)
        XCTAssertEqual(response.error?.code, .protocolVersionMismatch)
    }

    func testAlreadyExpiredDeadlineIsRejected() throws {
        let descriptor = try startServer()
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(fd) }

        let request = BrokerRequest(deadline: Date().addingTimeInterval(-5), sessionToken: descriptor.sessionToken, operation: .ping)
        TestIPCClient.send(try JSONEncoder().encode(request), on: fd)

        let responseData = try XCTUnwrap(TestIPCClient.readOneFrame(from: fd))
        let response = try decodeResponse(responseData)
        XCTAssertNil(response.result)
        XCTAssertEqual(response.error?.code, .deadlineExceeded)
    }

    func testMalformedJSONPayloadReturnsMalformedRequestWithSentinelID() throws {
        let descriptor = try startServer()
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(fd) }

        TestIPCClient.send(Data("not valid json".utf8), on: fd)

        let responseData = try XCTUnwrap(TestIPCClient.readOneFrame(from: fd))
        let response = try decodeResponse(responseData)
        XCTAssertEqual(response.requestID, BrokerResponse.unknownRequestID)
        XCTAssertEqual(response.error?.code, .malformedRequest)
    }

    // MARK: - Over-limit frame

    func testOverLimitFrameClosesConnectionWithoutCrashingServer() throws {
        let descriptor = try startServer()
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))

        // A length prefix advertising far more than IPCProtocol.maxFramePayloadBytes,
        // never followed by that much data.
        var oversizedLength = UInt32(50_000_000).bigEndian
        let lengthPrefix = Data(bytes: &oversizedLength, count: 4)
        TestIPCClient.sendRaw(lengthPrefix, on: fd)
        TestIPCClient.sendRaw(Data("only a few bytes".utf8), on: fd)

        XCTAssertTrue(TestIPCClient.expectNoDataOrEOF(from: fd), "server must close the connection rather than respond or hang")
        close(fd)

        // The server itself must still be healthy for a fresh connection.
        let secondFD = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(secondFD) }
        let request = BrokerRequest(deadline: Date().addingTimeInterval(30), sessionToken: descriptor.sessionToken, operation: .ping)
        TestIPCClient.send(try JSONEncoder().encode(request), on: secondFD)
        let responseData = try XCTUnwrap(TestIPCClient.readOneFrame(from: secondFD))
        let response = try decodeResponse(responseData)
        XCTAssertEqual(response.result, .pong)
    }

    // MARK: - Peer rejection seam

    func testMismatchedPeerUIDIsRejectedWithoutAnyResponse() throws {
        let descriptor = try startServer(peerCredentialLookup: FakePeerCredentialLookup(uid: 99999))
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(fd) }

        let request = BrokerRequest(deadline: Date().addingTimeInterval(30), sessionToken: descriptor.sessionToken, operation: .ping)
        TestIPCClient.send(try JSONEncoder().encode(request), on: fd)

        XCTAssertTrue(TestIPCClient.expectNoDataOrEOF(from: fd), "a connection from an unauthorized peer UID must never receive a response")
    }

    func testUnreadablePeerCredentialsAreTreatedAsUnauthorized() throws {
        let descriptor = try startServer(peerCredentialLookup: FakePeerCredentialLookup(uid: nil))
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(fd) }

        XCTAssertTrue(TestIPCClient.expectNoDataOrEOF(from: fd))
    }

    func testMatchingPeerUIDIsAcceptedThroughTheRealSyscallPath() throws {
        // Uses the default LivePeerCredentialLookup (real getpeereid()); a
        // same-process test client always presents the same UID as the
        // server, so this exercises the real "authorized" branch of the
        // syscall path end-to-end.
        let descriptor = try startServer()
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(fd) }

        let request = BrokerRequest(deadline: Date().addingTimeInterval(30), sessionToken: descriptor.sessionToken, operation: .ping)
        TestIPCClient.send(try JSONEncoder().encode(request), on: fd)
        let responseData = try XCTUnwrap(TestIPCClient.readOneFrame(from: fd))
        XCTAssertEqual(try decodeResponse(responseData).result, .pong)
    }

    // MARK: - Stop lifecycle

    func testStopClosesActiveConnectionAndRemovesSocketAndDescriptor() throws {
        let descriptor = try startServer()
        let fd = try XCTUnwrap(TestIPCClient.connect(path: descriptor.socketPath))
        defer { close(fd) }

        // Give the accept loop a moment to actually accept and register
        // this connection before stopping, so the assertion below exercises
        // closing an established connection (the real "helper mid-request,
        // user disables the Privacy toggle" scenario) rather than racing
        // the listener's own shutdown of a connection still sitting
        // unaccepted in the kernel backlog.
        Thread.sleep(forTimeInterval: 0.1)

        server.stop()

        let start = Date()
        let closed = TestIPCClient.expectNoDataOrEOF(from: fd)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(closed, "an already-open connection must be closed by stop()")
        XCTAssertLessThan(elapsed, 1.0, "stop() must close an active connection promptly rather than leaving the peer to hit its own read timeout")

        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptor.socketPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("broker.json").path))
    }

    func testStopIsSafeToCallWhenNotRunning() {
        server = BrokerIPCServer(broker: makeTestBroker(), baseDirectory: baseDirectory)
        server.stop() // must not crash/throw
        XCTAssertFalse(server.isRunningNow)
    }

    func testRestartAfterStopRotatesSocketAndToken() throws {
        let first = try startServer()
        server.stop()
        Thread.sleep(forTimeInterval: 0.05)

        server = BrokerIPCServer(broker: makeTestBroker(), baseDirectory: baseDirectory)
        let second = try server.start()

        XCTAssertNotEqual(first.sessionToken, second.sessionToken)
    }
}

// MARK: - Pure PeerAuthorization decision logic

final class PeerAuthorizationTests: XCTestCase {
    func testMatchingUIDIsAuthorized() {
        XCTAssertTrue(PeerAuthorization.isAuthorized(peerUID: 501, expectedUID: 501))
    }

    func testMismatchedUIDIsNotAuthorized() {
        XCTAssertFalse(PeerAuthorization.isAuthorized(peerUID: 502, expectedUID: 501))
    }

    func testNilUIDIsNotAuthorized() {
        XCTAssertFalse(PeerAuthorization.isAuthorized(peerUID: nil, expectedUID: 501))
    }
}
