import Foundation

/// Contents of `~/Library/Application Support/BerryShot/MCP/broker.json`,
/// written atomically by the GUI with file mode `0600` inside a `0700`
/// directory (`05-mcp-server-contract.md` section 7).
public struct BrokerDescriptor: Codable, Sendable, Equatable {
    public let protocolVersion: UInt16
    public let socketPath: String
    public let guiPID: Int32
    public let expiresAt: Date
    public let sessionToken: String

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case socketPath = "socket_path"
        case guiPID = "gui_pid"
        case expiresAt = "expires_at"
        case sessionToken = "session_token"
    }

    public init(
        protocolVersion: UInt16,
        socketPath: String,
        guiPID: Int32,
        expiresAt: Date,
        sessionToken: String
    ) {
        self.protocolVersion = protocolVersion
        self.socketPath = socketPath
        self.guiPID = guiPID
        self.expiresAt = expiresAt
        self.sessionToken = sessionToken
    }
}

/// Pure, unit-testable mirror of the trust checks
/// `05-mcp-server-contract.md` section 7 requires before a helper connects:
/// "Helper rejects a descriptor not owned by the current UID, with
/// group/other permission bits, expired timestamp, or dead/mismatched GUI
/// PID. It never searches arbitrary socket paths."
///
/// All filesystem/process inspection (stat, PID liveness) happens in the
/// caller (`BrokerDescriptorLoader` in the helper target); this type only
/// encodes the pass/fail decision so it is testable without touching disk
/// or process state.
public enum BrokerDescriptorValidation {
    public enum Failure: Equatable, Sendable {
        case notOwnedByCurrentUser
        case groupOrOtherPermissionBitsSet
        case expired
        case processNotAlive
        case protocolVersionMismatch
    }

    /// - Parameters:
    ///   - fileOwnerUID: UID that owns `broker.json` on disk.
    ///   - filePermissionBits: The low 9 permission bits of `broker.json`'s mode.
    ///   - currentUID: The helper process's own effective UID.
    ///   - expectedProtocolVersion: `IPCProtocol.currentVersion` as compiled into the helper.
    ///   - processIsAlive: Whether `descriptor.guiPID` currently identifies a live process.
    /// - Returns: The first failing check, or `nil` if the descriptor is trustworthy.
    public static func validate(
        descriptor: BrokerDescriptor,
        fileOwnerUID: UInt32,
        filePermissionBits: UInt16,
        currentUID: UInt32,
        expectedProtocolVersion: UInt16,
        processIsAlive: Bool,
        now: Date = Date()
    ) -> Failure? {
        guard fileOwnerUID == currentUID else { return .notOwnedByCurrentUser }
        guard filePermissionBits & 0o077 == 0 else { return .groupOrOtherPermissionBitsSet }
        guard descriptor.expiresAt > now else { return .expired }
        guard processIsAlive else { return .processNotAlive }
        guard descriptor.protocolVersion == expectedProtocolVersion else { return .protocolVersionMismatch }
        return nil
    }
}
