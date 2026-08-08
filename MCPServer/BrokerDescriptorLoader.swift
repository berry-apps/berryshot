import Foundation
import BerryShotIPC
#if canImport(Darwin)
import Darwin
#endif

/// Reads and validates `broker.json` from disk. Never searches for the
/// socket/descriptor anywhere other than the one fixed, documented path
/// (`05-mcp-server-contract.md` section 7: "It never searches arbitrary
/// socket paths").
public enum BrokerDescriptorLoader {
    public enum LoadError: Error, Sendable, Equatable {
        case descriptorUnavailable
        case descriptorUnreadable
        case invalid(BrokerDescriptorValidation.Failure)
    }

    public static func load(
        from directory: URL,
        expectedProtocolVersion: UInt16 = IPCProtocol.currentVersion,
        currentUID: UInt32 = UInt32(getuid())
    ) throws -> BrokerDescriptor {
        let descriptorURL = directory.appendingPathComponent("broker.json")
        let path = descriptorURL.path

        var statInfo = stat()
        guard stat(path, &statInfo) == 0 else {
            throw LoadError.descriptorUnavailable
        }
        let fileOwnerUID = UInt32(statInfo.st_uid)
        let filePermissionBits = UInt16(statInfo.st_mode & 0o777)

        guard let data = FileManager.default.contents(atPath: path) else {
            throw LoadError.descriptorUnreadable
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let descriptor = try? decoder.decode(BrokerDescriptor.self, from: data) else {
            throw LoadError.descriptorUnreadable
        }

        let processIsAlive = kill(pid_t(descriptor.guiPID), 0) == 0

        if let failure = BrokerDescriptorValidation.validate(
            descriptor: descriptor,
            fileOwnerUID: fileOwnerUID,
            filePermissionBits: filePermissionBits,
            currentUID: currentUID,
            expectedProtocolVersion: expectedProtocolVersion,
            processIsAlive: processIsAlive
        ) {
            throw LoadError.invalid(failure)
        }

        return descriptor
    }
}
