import Foundation
import BerryShotIPC

/// Owns every WP8 documentation session: the allowlisted bundle identifier,
/// mode, TTL, artifact limit, locked-in redaction policy/style, recorded
/// steps/coverage, and the per-session Stop flag every long-running
/// operation (`wait_for_ui`) polls
/// (`06-agent-documentation-security.md` section 2's session model and
/// section 6's user controls: "allowlist... TTL, artifact-limit,
/// redaction-policy... Stop control").
///
/// This actor knows nothing about AX, ScreenCaptureKit, or IPC framing —
/// `CaptureBroker` is the only caller, exactly like `CaptureArtifactStore`.
public actor DocumentationSessionManager {
    public enum SessionError: Error, Sendable, Equatable {
        case invalidArgument(String)
        case notFound
        case expired
        case stopped
        case artifactLimitReached
    }

    public struct Session: Sendable {
        public let id: String
        public let bundleIdentifier: String
        public let displayName: String
        public let mode: DocumentationSessionMode
        public let redactionPolicy: IPCRedactionPolicy
        public let redactionStyle: IPCRedactionStyle
        public let allowLaunch: Bool
        public let maxArtifacts: Int
        public let createdAt: Date
        public var expiresAt: Date
        public var isStopped: Bool = false
        public var steps: [DocumentationStepDTO] = []
        public var lastActionAt: Date
        public var lastActionDescription: String

        public var artifactCount: Int { steps.reduce(0) { $0 + $1.captureIDs.count } }
    }

    public static let minTTLSeconds = 60
    public static let maxTTLSeconds = 4 * 60 * 60
    public static let minMaxArtifacts = 1
    public static let maxMaxArtifacts = 200
    public static let maxDisplayNameLength = 120
    public static let maxFeatureNameLength = 200
    public static let maxNavigationSummaryEntries = 20
    public static let maxNoteLength = 500
    public static let maxNotesCount = 10

    private var sessions: [String: Session] = [:]
    /// Fired (best-effort, on the main actor) after every mutation so the
    /// GUI's persistent indicator can reflect active sessions
    /// (`06-agent-documentation-security.md` section 6: "Persistent
    /// menu-bar indicator while a broker session is connected... Show
    /// client name, target bundle ID, mode, elapsed time, and last
    /// action"). `nil` in tests that do not care about the indicator.
    private let onChange: (@Sendable ([DocumentationSessionDTO]) -> Void)?
    /// Injectable clock so TTL expiry is deterministically testable without
    /// a real wall-clock sleep (`DocumentationSessionManagerTests`
    /// fast-forwards a fake clock instead of waiting out a multi-minute
    /// TTL). Defaults to the real system clock in production.
    private let clock: @Sendable () -> Date

    public init(onChange: (@Sendable ([DocumentationSessionDTO]) -> Void)? = nil, clock: @escaping @Sendable () -> Date = Date.init) {
        self.onChange = onChange
        self.clock = clock
    }

    // MARK: - Lifecycle

    public func begin(_ request: DocumentationSessionBeginRequest) throws -> DocumentationSessionDTO {
        guard !request.bundleIdentifier.isEmpty, request.bundleIdentifier.count <= 255 else {
            throw SessionError.invalidArgument("bundle_id is required and must be at most 255 characters")
        }
        guard !request.displayName.isEmpty, request.displayName.count <= Self.maxDisplayNameLength else {
            throw SessionError.invalidArgument("display_name is required and must be at most \(Self.maxDisplayNameLength) characters")
        }
        guard request.ttlSeconds >= Self.minTTLSeconds, request.ttlSeconds <= Self.maxTTLSeconds else {
            throw SessionError.invalidArgument("ttl_seconds must be between \(Self.minTTLSeconds) and \(Self.maxTTLSeconds)")
        }
        guard request.maxArtifacts >= Self.minMaxArtifacts, request.maxArtifacts <= Self.maxMaxArtifacts else {
            throw SessionError.invalidArgument("max_artifacts must be between \(Self.minMaxArtifacts) and \(Self.maxMaxArtifacts)")
        }
        // Locked default per `10-decisions-risks-open-questions.md` section 4
        // item 4 and `06-agent-documentation-security.md` section 2: a
        // session may only ever run at the strictest redaction policy this
        // product supports for MCP-exposed captures. A caller may omit the
        // field (gets the locked default) or explicitly confirm it, but
        // cannot request anything weaker — this is enforced here, not left
        // to the caller's honesty.
        if let requested = request.redactionPolicy, requested != .required {
            throw SessionError.invalidArgument("redaction_policy must be 'required' for documentation sessions")
        }

        let sanitizedName = Self.sanitize(request.displayName, maxLength: Self.maxDisplayNameLength)
        let now = clock()
        let id = UUID().uuidString
        let session = Session(
            id: id,
            bundleIdentifier: request.bundleIdentifier,
            displayName: sanitizedName,
            mode: request.mode,
            redactionPolicy: .required,
            redactionStyle: request.redactionStyle,
            allowLaunch: request.allowLaunch,
            maxArtifacts: request.maxArtifacts,
            createdAt: now,
            expiresAt: now.addingTimeInterval(TimeInterval(request.ttlSeconds)),
            steps: [],
            lastActionAt: now,
            lastActionDescription: "Session started"
        )
        sessions[id] = session
        notifyChange()
        return dto(for: session)
    }

    public func status(sessionID: String) throws -> DocumentationSessionDTO {
        dto(for: try activeSession(sessionID))
    }

    /// Every WP8 operation other than `begin` calls this first. Applies lazy
    /// TTL expiry (mirroring `CaptureArtifactStore.record(for:)`) and rejects
    /// a stopped session, so callers never need to duplicate these checks.
    public func activeSession(_ sessionID: String) throws -> Session {
        guard let session = sessions[sessionID] else { throw SessionError.notFound }
        if session.isStopped { throw SessionError.stopped }
        guard clock() < session.expiresAt else {
            sessions.removeValue(forKey: sessionID)
            notifyChange()
            throw SessionError.expired
        }
        return session
    }

    /// Records one already-captured step. The caller (`CaptureBroker`) is
    /// responsible for verifying the target window's bundle identity and
    /// actually running the capture pipeline *before* calling this — this
    /// method only enforces the artifact budget and appends bookkeeping.
    @discardableResult
    public func recordStep(
        sessionID: String,
        captureID: String,
        feature: String,
        navigationSummary: [String],
        redactionStatus: IPCRedactionStatus,
        verification: DocumentationCoverageState,
        notes: [String]
    ) throws -> DocumentationSessionDTO {
        var session = try activeSession(sessionID)
        guard session.artifactCount < session.maxArtifacts else {
            throw SessionError.artifactLimitReached
        }

        let step = DocumentationStepDTO(
            stepID: UUID().uuidString,
            feature: Self.sanitize(feature, maxLength: Self.maxFeatureNameLength),
            captureIDs: [captureID],
            navigationSummary: navigationSummary.prefix(Self.maxNavigationSummaryEntries).map { Self.sanitize($0, maxLength: 200) },
            redactionStatus: redactionStatus,
            verification: verification,
            notes: notes.prefix(Self.maxNotesCount).map { Self.sanitize($0, maxLength: Self.maxNoteLength) },
            recordedAt: ISO8601DateFormatter().string(from: clock())
        )
        session.steps.append(step)
        session.lastActionAt = clock()
        session.lastActionDescription = "Captured step: \(step.feature)"
        sessions[sessionID] = session
        notifyChange()
        return dto(for: session)
    }

    /// Records a non-capture action (AX inspect/action/wait/launch) for the
    /// indicator's "last action" field without touching the artifact budget
    /// or steps list.
    public func touchAction(sessionID: String, description: String) {
        guard var session = sessions[sessionID] else { return }
        session.lastActionAt = clock()
        session.lastActionDescription = Self.sanitize(description, maxLength: 200)
        sessions[sessionID] = session
        notifyChange()
    }

    /// Ends the session immediately: marks it stopped so
    /// ``activeSession(_:)`` rejects any further work under it, and sets a
    /// flag ``isStopRequested(_:)`` a long-running in-flight call (only
    /// `wait_for_ui`'s bounded poll loop) checks every tick so it exits
    /// promptly instead of running to its full timeout
    /// (`06-agent-documentation-security.md` section 8: "Stop button
    /// cancels current wait/capture and future requests").
    @discardableResult
    public func end(sessionID: String) throws -> DocumentationSessionDTO {
        guard var session = sessions[sessionID] else { throw SessionError.notFound }
        session.isStopped = true
        session.lastActionAt = clock()
        session.lastActionDescription = "Session stopped"
        sessions[sessionID] = session
        notifyChange()
        return dto(for: session)
    }

    /// Polled by `wait_for_ui`'s bounded loop. Returns `true` once `end(...)`
    /// has been called (or the session expired/vanished), independent of
    /// the TTL check `activeSession(_:)` performs at call-start.
    public func isStopRequested(_ sessionID: String) -> Bool {
        guard let session = sessions[sessionID] else { return true }
        return session.isStopped
    }

    /// Stops every currently active session. Called when the global MCP
    /// broker Stop control is used (`MCPIntegrationSettings.disable()`), not
    /// only when one session's own `documentation_session_end` is called.
    public func stopAll() {
        for id in sessions.keys {
            sessions[id]?.isStopped = true
        }
        notifyChange()
    }

    // MARK: - DTO / indicator

    private func dto(for session: Session) -> DocumentationSessionDTO {
        let status: DocumentationSessionStatus
        if session.isStopped {
            status = .stopped
        } else if clock() >= session.expiresAt {
            status = .expired
        } else {
            status = .active
        }
        let coverage = DocumentationCoverageDTO(
            verified: session.steps.filter { $0.verification == .verified }.map(\.stepID),
            conditional: session.steps.filter { $0.verification == .conditional }.map(\.stepID),
            blocked: session.steps.filter { $0.verification == .blocked }.map(\.stepID),
            notAttempted: session.steps.filter { $0.verification == .notAttempted }.map(\.stepID)
        )
        let formatter = ISO8601DateFormatter()
        return DocumentationSessionDTO(
            sessionID: session.id,
            bundleIdentifier: session.bundleIdentifier,
            displayName: session.displayName,
            mode: session.mode,
            status: status,
            startedAt: formatter.string(from: session.createdAt),
            expiresAt: formatter.string(from: session.expiresAt),
            allowLaunch: session.allowLaunch,
            redactionPolicy: session.redactionPolicy,
            redactionStyle: session.redactionStyle,
            maxArtifacts: session.maxArtifacts,
            artifactCount: session.artifactCount,
            lastActionAt: formatter.string(from: session.lastActionAt),
            lastActionDescription: session.lastActionDescription,
            steps: session.steps,
            coverage: coverage
        )
    }

    private func notifyChange() {
        guard let onChange else { return }
        // Expired sessions are dropped from the visible indicator list
        // (still-stopped ones remain briefly so "Stopped" is visible)
        // instead of being pruned from `sessions` here — pruning stays
        // lazy, driven only by `activeSession(_:)`, so this read-only
        // snapshot never mutates state as a side effect of notifying.
        let visible = sessions.values.filter { clock() < $0.expiresAt }.map(dto(for:))
        onChange(visible)
    }

    private static func sanitize(_ text: String, maxLength: Int) -> String {
        let allowedScalars = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(allowedScalars))
        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength))
    }
}
