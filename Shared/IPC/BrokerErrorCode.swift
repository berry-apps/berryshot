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

    // MARK: - WP8 documentation-session / guarded-AX-automation error codes
    // (`06-agent-documentation-security.md`; new in this work package, but
    // part of the same stable MCP-tool-visible block as everything above).

    /// Unknown or already-removed `session_id`.
    case sessionNotFound = "session_not_found"
    /// `session_id` is well-formed but its TTL has elapsed.
    case sessionExpired = "session_expired"
    /// `session_id` was ended via `documentation_session_end` or the global
    /// Stop control; no further work is accepted under it.
    case sessionStopped = "session_stopped"
    /// A call targeted a window/application that does not belong to the
    /// session's allowlisted bundle identifier
    /// (`06-agent-documentation-security.md` section 8: "Attempt action
    /// against a non-session bundle ID: rejected").
    case bundleNotAllowed = "bundle_not_allowed"
    /// The `max_artifacts` budget for this session has been reached.
    case artifactLimitReached = "artifact_limit_reached"
    /// An `element_ref` failed session/PID/generation/TTL revalidation
    /// (`06-agent-documentation-security.md` section 8: "Reuse stale element
    /// reference after PID/window change: rejected").
    case elementStale = "element_stale"
    /// The requested action/element was rejected by the secure-field or
    /// destructive/external-side-effect guard, or is not among this
    /// element's real AX-supported actions
    /// (`06-agent-documentation-security.md` section 8: "Attempt value
    /// read/write on secure field: rejected"; "Attempt blocked role/action
    /// such as Delete/Buy/Send: rejected").
    case actionBlocked = "action_blocked"
    /// `launch_application` was called without the session's `allowLaunch`
    /// flag, without this call's own `approve` flag, or against a bundle
    /// identifier other than the session's.
    case launchNotApproved = "launch_not_approved"
    /// `activate_application`/`inspect_ui`/`perform_ui_action`/`wait_for_ui`
    /// require the session's target application to already be running (only
    /// `launch_application` starts a new process).
    case applicationNotRunning = "application_not_running"

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
