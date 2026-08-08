import Foundation

/// The bounded set of operations `CaptureBroker` accepts in this work
/// package: read-only discovery plus a connectivity/lifecycle pair. Capture
/// and redaction operations are explicitly out of scope for WP6
/// (`08-implementation-work-packages.md` WP6 goal: "without yet exposing
/// full production tools").
///
/// `Codable` conformance is written by hand rather than relying on Swift's
/// automatic enum-with-associated-values synthesis: the wire format for a
/// versioned cross-process protocol must be a format this file defines and
/// controls, not whatever the compiler happens to synthesize for a given
/// toolchain.
public enum BrokerOperation: Sendable, Equatable {
    /// Cheap liveness/handshake check; does not touch ScreenCaptureKit or AX.
    case ping
    case permissionsStatus
    case listApplications(ListApplicationsRequest)
    case listWindows(ListWindowsRequest)
    /// Best-effort cancellation of another in-flight or still-queued
    /// request, identified by its `requestID`. Always acknowledged; racing
    /// with a request that already finished is not an error.
    case cancel(UUID)
}

extension BrokerOperation: Codable {
    private enum Kind: String, Codable {
        case ping
        case permissionsStatus
        case listApplications
        case listWindows
        case cancel
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .ping:
            self = .ping
        case .permissionsStatus:
            self = .permissionsStatus
        case .listApplications:
            self = .listApplications(try container.decode(ListApplicationsRequest.self, forKey: .payload))
        case .listWindows:
            self = .listWindows(try container.decode(ListWindowsRequest.self, forKey: .payload))
        case .cancel:
            self = .cancel(try container.decode(UUID.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ping:
            try container.encode(Kind.ping, forKey: .type)
        case .permissionsStatus:
            try container.encode(Kind.permissionsStatus, forKey: .type)
        case .listApplications(let payload):
            try container.encode(Kind.listApplications, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .listWindows(let payload):
            try container.encode(Kind.listWindows, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .cancel(let requestID):
            try container.encode(Kind.cancel, forKey: .type)
            try container.encode(requestID, forKey: .payload)
        }
    }
}

/// Results mirroring ``BrokerOperation`` one-for-one. Same rationale for
/// hand-written `Codable` as above.
public enum BrokerResult: Sendable, Equatable {
    case pong
    case permissionsStatus(PermissionsStatusDTO)
    case applications(ListApplicationsResult)
    case windows(ListWindowsResult)
    case cancelAcknowledged
}

extension BrokerResult: Codable {
    private enum Kind: String, Codable {
        case pong
        case permissionsStatus
        case applications
        case windows
        case cancelAcknowledged
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .pong:
            self = .pong
        case .permissionsStatus:
            self = .permissionsStatus(try container.decode(PermissionsStatusDTO.self, forKey: .payload))
        case .applications:
            self = .applications(try container.decode(ListApplicationsResult.self, forKey: .payload))
        case .windows:
            self = .windows(try container.decode(ListWindowsResult.self, forKey: .payload))
        case .cancelAcknowledged:
            self = .cancelAcknowledged
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pong:
            try container.encode(Kind.pong, forKey: .type)
        case .permissionsStatus(let payload):
            try container.encode(Kind.permissionsStatus, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .applications(let payload):
            try container.encode(Kind.applications, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .windows(let payload):
            try container.encode(Kind.windows, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .cancelAcknowledged:
            try container.encode(Kind.cancelAcknowledged, forKey: .type)
        }
    }
}
