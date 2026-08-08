import Foundation

/// Stable, versioned error codes returned by the broker over IPC.
///
/// The first block matches `05-mcp-server-contract.md` section 4's MCP tool
/// error codes verbatim, so a later work package can surface them to an MCP
/// client unchanged. The second block (`unauthorized`, `protocolVersionMismatch`,
/// `malformedRequest`) exists only below the MCP tool layer, at the IPC
/// transport boundary; a well-behaved helper never lets these reach an MCP
/// tool result and instead maps them to `berryshotUnavailable`/
/// `internalError` before returning a tool response, since an MCP client has
/// no useful action to take on "your session token was wrong."
public enum BrokerErrorCode: String, Codable, Sendable, Equatable {
    // MARK: - Stable execution error codes (05-mcp-server-contract.md section 4)

    case permissionDenied = "permission_denied"
    case restartRequired = "restart_required"
    case berryshotUnavailable = "berryshot_unavailable"
    case brokerUnavailable = "broker_unavailable"
    case invalidArgument = "invalid_argument"
    case applicationNotFound = "application_not_found"
    case windowNotAvailable = "window_not_available"
    case windowIdentityChanged = "window_identity_changed"
    case redactionUnavailable = "redaction_unavailable"
    case redactionReviewRequired = "redaction_review_required"
    case deadlineExceeded = "deadline_exceeded"
    case cancelled = "cancelled"
    case resourceNotFound = "resource_not_found"
    case resourceExpired = "resource_expired"
    case rateLimited = "rate_limited"
    case internalError = "internal_error"

    // MARK: - IPC transport-layer-only codes (not part of the MCP tool contract)

    case unauthorized = "unauthorized"
    case protocolVersionMismatch = "protocol_version_mismatch"
    case malformedRequest = "malformed_request"
}

/// A sanitized, user-facing broker error. `message` must never contain a raw
/// exception description, filesystem path, stack trace, recognized
/// sensitive text, or local username
/// (`05-mcp-server-contract.md` section 4: "Do not expose stack traces,
/// recognized sensitive text, local usernames, or arbitrary paths").
public struct BrokerErrorDTO: Codable, Sendable, Equatable {
    public let code: BrokerErrorCode
    public let message: String

    public init(code: BrokerErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}
