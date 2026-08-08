import XCTest
@testable import BerryShotIPC

final class BrokerDescriptorValidationTests: XCTestCase {
    private func makeDescriptor(
        protocolVersion: UInt16 = IPCProtocol.currentVersion,
        expiresAt: Date = Date().addingTimeInterval(3600)
    ) -> BrokerDescriptor {
        BrokerDescriptor(
            protocolVersion: protocolVersion,
            socketPath: "/Users/test/Library/Application Support/BerryShot/MCP/broker.sock",
            guiPID: 4242,
            expiresAt: expiresAt,
            sessionToken: "deadbeef"
        )
    }

    func testValidDescriptorPasses() {
        let failure = BrokerDescriptorValidation.validate(
            descriptor: makeDescriptor(),
            fileOwnerUID: 501,
            filePermissionBits: 0o600,
            currentUID: 501,
            expectedProtocolVersion: IPCProtocol.currentVersion,
            processIsAlive: true
        )
        XCTAssertNil(failure)
    }

    func testRejectsDescriptorNotOwnedByCurrentUser() {
        let failure = BrokerDescriptorValidation.validate(
            descriptor: makeDescriptor(),
            fileOwnerUID: 999,
            filePermissionBits: 0o600,
            currentUID: 501,
            expectedProtocolVersion: IPCProtocol.currentVersion,
            processIsAlive: true
        )
        XCTAssertEqual(failure, .notOwnedByCurrentUser)
    }

    func testRejectsGroupReadableDescriptor() {
        let failure = BrokerDescriptorValidation.validate(
            descriptor: makeDescriptor(),
            fileOwnerUID: 501,
            filePermissionBits: 0o640,
            currentUID: 501,
            expectedProtocolVersion: IPCProtocol.currentVersion,
            processIsAlive: true
        )
        XCTAssertEqual(failure, .groupOrOtherPermissionBitsSet)
    }

    func testRejectsWorldReadableDescriptor() {
        let failure = BrokerDescriptorValidation.validate(
            descriptor: makeDescriptor(),
            fileOwnerUID: 501,
            filePermissionBits: 0o604,
            currentUID: 501,
            expectedProtocolVersion: IPCProtocol.currentVersion,
            processIsAlive: true
        )
        XCTAssertEqual(failure, .groupOrOtherPermissionBitsSet)
    }

    func testRejectsExpiredDescriptor() {
        let failure = BrokerDescriptorValidation.validate(
            descriptor: makeDescriptor(expiresAt: Date().addingTimeInterval(-1)),
            fileOwnerUID: 501,
            filePermissionBits: 0o600,
            currentUID: 501,
            expectedProtocolVersion: IPCProtocol.currentVersion,
            processIsAlive: true
        )
        XCTAssertEqual(failure, .expired)
    }

    func testRejectsDescriptorWhoseGUIProcessIsNotAlive() {
        let failure = BrokerDescriptorValidation.validate(
            descriptor: makeDescriptor(),
            fileOwnerUID: 501,
            filePermissionBits: 0o600,
            currentUID: 501,
            expectedProtocolVersion: IPCProtocol.currentVersion,
            processIsAlive: false
        )
        XCTAssertEqual(failure, .processNotAlive)
    }

    func testRejectsProtocolVersionMismatch() {
        let failure = BrokerDescriptorValidation.validate(
            descriptor: makeDescriptor(protocolVersion: 999),
            fileOwnerUID: 501,
            filePermissionBits: 0o600,
            currentUID: 501,
            expectedProtocolVersion: IPCProtocol.currentVersion,
            processIsAlive: true
        )
        XCTAssertEqual(failure, .protocolVersionMismatch)
    }

    /// Ownership is checked before permission bits — a descriptor an attacker
    /// planted (owned by a different UID) must never be accepted merely
    /// because its mode bits happen to look strict.
    func testOwnershipIsCheckedBeforePermissionBits() {
        let failure = BrokerDescriptorValidation.validate(
            descriptor: makeDescriptor(),
            fileOwnerUID: 999,
            filePermissionBits: 0o777,
            currentUID: 501,
            expectedProtocolVersion: IPCProtocol.currentVersion,
            processIsAlive: true
        )
        XCTAssertEqual(failure, .notOwnedByCurrentUser)
    }

    func testDescriptorEncodesSnakeCaseKeysOnTheWire() throws {
        let descriptor = makeDescriptor()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(descriptor)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        for key in ["protocol_version", "socket_path", "gui_pid", "expires_at", "session_token"] {
            XCTAssertTrue(json.contains(key), "expected \(key) in \(json)")
        }
    }
}
