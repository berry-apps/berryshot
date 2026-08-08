import Foundation

/// WP8 documentation-session wire types
/// (`06-agent-documentation-security.md` section 2). A session is the
/// allowlist/mode/TTL/artifact-limit/redaction-policy boundary every later
/// WP8 operation (`documentationSessionCaptureStep`, `inspectUI`,
/// `performUIAction`, `waitForUI`, `launchApplication`,
/// `activateApplication`) must be validated against — none of those
/// operations accept a bundle identifier of their own; they only ever act on
/// the single bundle the session was created for.
public enum DocumentationSessionMode: String, Codable, Sendable, Equatable {
    case readOnly
    case interactive
}

public enum DocumentationSessionStatus: String, Codable, Sendable, Equatable {
    case active
    case stopped
    case expired
}

/// Evidence-based coverage state for one documented step or one aggregate
/// session. `06-agent-documentation-security.md` section 2: "The agent must
/// not claim feature completeness from AX traversal alone. Coverage is
/// evidence-based and preserves blocked/unverified states." There is no
/// "complete" case anywhere in this enum by construction.
public enum DocumentationCoverageState: String, Codable, Sendable, Equatable {
    case verified
    case conditional
    case blocked
    case notAttempted = "not_attempted"
}

public struct DocumentationSessionBeginRequest: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let displayName: String
    public let mode: DocumentationSessionMode
    /// `nil` uses the mode-appropriate locked default
    /// (`10-decisions-risks-open-questions.md` section 4 item 4: "MCP
    /// redaction, when enabled, defaults to `required + solid`"; section 2
    /// of `06-agent-documentation-security.md`: "interactive external
    /// sessions default to `required` when enabled"). A caller may only
    /// request a *stricter* explicit policy than the default carries; see
    /// `DocumentationSessionManager` for the exact rule.
    public let redactionPolicy: IPCRedactionPolicy?
    public let redactionStyle: IPCRedactionStyle
    public let ttlSeconds: Int
    public let maxArtifacts: Int
    /// Session-level precondition for `launch_application`
    /// (`06-agent-documentation-security.md` section 4: "Launching an absent
    /// app requires `allowLaunch: true` in the session plus per-call user
    /// approval"). Has no effect on `activate_application`, which never
    /// launches anything.
    public let allowLaunch: Bool

    public init(
        bundleIdentifier: String,
        displayName: String,
        mode: DocumentationSessionMode,
        redactionPolicy: IPCRedactionPolicy? = nil,
        redactionStyle: IPCRedactionStyle = .solid,
        ttlSeconds: Int,
        maxArtifacts: Int,
        allowLaunch: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.mode = mode
        self.redactionPolicy = redactionPolicy
        self.redactionStyle = redactionStyle
        self.ttlSeconds = ttlSeconds
        self.maxArtifacts = maxArtifacts
        self.allowLaunch = allowLaunch
    }
}

public struct DocumentationStepDTO: Codable, Sendable, Equatable {
    public let stepID: String
    public let feature: String
    public let captureIDs: [String]
    public let navigationSummary: [String]
    public let redactionStatus: IPCRedactionStatus
    public let verification: DocumentationCoverageState
    public let notes: [String]
    public let recordedAt: String

    private enum CodingKeys: String, CodingKey {
        case stepID = "step_id"
        case feature
        case captureIDs = "capture_ids"
        case navigationSummary = "navigation_summary"
        case redactionStatus = "redaction_status"
        case verification
        case notes
        case recordedAt = "recorded_at"
    }

    public init(
        stepID: String,
        feature: String,
        captureIDs: [String],
        navigationSummary: [String],
        redactionStatus: IPCRedactionStatus,
        verification: DocumentationCoverageState,
        notes: [String],
        recordedAt: String
    ) {
        self.stepID = stepID
        self.feature = feature
        self.captureIDs = captureIDs
        self.navigationSummary = navigationSummary
        self.redactionStatus = redactionStatus
        self.verification = verification
        self.notes = notes
        self.recordedAt = recordedAt
    }
}

/// Mirrors the `coverage` object in `06-agent-documentation-security.md`
/// section 2's example manifest exactly: one bucket of step IDs per
/// ``DocumentationCoverageState`` case.
public struct DocumentationCoverageDTO: Codable, Sendable, Equatable {
    public let verified: [String]
    public let conditional: [String]
    public let blocked: [String]
    public let notAttempted: [String]

    private enum CodingKeys: String, CodingKey {
        case verified
        case conditional
        case blocked
        case notAttempted = "not_attempted"
    }

    public init(verified: [String], conditional: [String], blocked: [String], notAttempted: [String]) {
        self.verified = verified
        self.conditional = conditional
        self.blocked = blocked
        self.notAttempted = notAttempted
    }

    public static let empty = DocumentationCoverageDTO(verified: [], conditional: [], blocked: [], notAttempted: [])
}

/// The session manifest. Returned by `documentation_session_begin`,
/// `documentation_session_status`, `documentation_session_capture_step` (the
/// session's state *after* recording the step), and
/// `documentation_session_end`, so a client always sees the same shape
/// regardless of which call produced it.
public struct DocumentationSessionDTO: Codable, Sendable, Equatable {
    public let sessionID: String
    public let bundleIdentifier: String
    public let displayName: String
    public let mode: DocumentationSessionMode
    public let status: DocumentationSessionStatus
    public let startedAt: String
    public let expiresAt: String
    public let allowLaunch: Bool
    public let redactionPolicy: IPCRedactionPolicy
    public let redactionStyle: IPCRedactionStyle
    public let maxArtifacts: Int
    public let artifactCount: Int
    public let lastActionAt: String
    public let lastActionDescription: String
    public let steps: [DocumentationStepDTO]
    public let coverage: DocumentationCoverageDTO

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case bundleIdentifier = "bundle_id"
        case displayName = "display_name"
        case mode
        case status
        case startedAt = "started_at"
        case expiresAt = "expires_at"
        case allowLaunch = "allow_launch"
        case redactionPolicy = "redaction_policy"
        case redactionStyle = "redaction_style"
        case maxArtifacts = "max_artifacts"
        case artifactCount = "artifact_count"
        case lastActionAt = "last_action_at"
        case lastActionDescription = "last_action_description"
        case steps
        case coverage
    }

    public init(
        sessionID: String,
        bundleIdentifier: String,
        displayName: String,
        mode: DocumentationSessionMode,
        status: DocumentationSessionStatus,
        startedAt: String,
        expiresAt: String,
        allowLaunch: Bool,
        redactionPolicy: IPCRedactionPolicy,
        redactionStyle: IPCRedactionStyle,
        maxArtifacts: Int,
        artifactCount: Int,
        lastActionAt: String,
        lastActionDescription: String,
        steps: [DocumentationStepDTO],
        coverage: DocumentationCoverageDTO
    ) {
        self.sessionID = sessionID
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.mode = mode
        self.status = status
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.allowLaunch = allowLaunch
        self.redactionPolicy = redactionPolicy
        self.redactionStyle = redactionStyle
        self.maxArtifacts = maxArtifacts
        self.artifactCount = artifactCount
        self.lastActionAt = lastActionAt
        self.lastActionDescription = lastActionDescription
        self.steps = steps
        self.coverage = coverage
    }
}

public struct DocumentationSessionStatusRequest: Codable, Sendable, Equatable {
    public let sessionID: String
    public init(sessionID: String) { self.sessionID = sessionID }
}

public struct DocumentationSessionEndRequest: Codable, Sendable, Equatable {
    public let sessionID: String
    public init(sessionID: String) { self.sessionID = sessionID }
}

/// `documentation_session_capture_step` deliberately does not accept its own
/// `redaction_policy`/`redaction_style`/`expected_bundle_id` the way
/// `capture_window` does: every field that could let a caller widen scope
/// beyond what `documentation_session_begin` already locked in is taken from
/// the session record instead, never from this per-call request
/// (`06-agent-documentation-security.md` anti-pattern guard: "No
/// agent-controlled arbitrary artifact/output directory" — the same
/// no-per-call-scope-widening principle applies to redaction/target here).
public struct DocumentationSessionCaptureStepRequest: Codable, Sendable, Equatable {
    public let sessionID: String
    public let windowID: UInt32
    public let feature: String
    public let navigationSummary: [String]
    public let verification: DocumentationCoverageState
    public let notes: [String]
    public let ocr: Bool

    public init(
        sessionID: String,
        windowID: UInt32,
        feature: String,
        navigationSummary: [String],
        verification: DocumentationCoverageState,
        notes: [String],
        ocr: Bool = false
    ) {
        self.sessionID = sessionID
        self.windowID = windowID
        self.feature = feature
        self.navigationSummary = navigationSummary
        self.verification = verification
        self.notes = notes
        self.ocr = ocr
    }
}
