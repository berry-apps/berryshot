import Foundation
import BerryShotIPC
@preconcurrency import ApplicationServices
import CoreGraphics

/// A sanitized, typed error `CaptureBroker` throws internally. `BrokerIPCServer`
/// converts this to a `BrokerErrorDTO` before it crosses the IPC boundary;
/// `message` follows the same "no stack traces/paths/usernames" rule as
/// `BrokerErrorDTO` itself.
public struct BrokerOperationError: Error, Sendable {
    public let code: BrokerErrorCode
    public let message: String

    public init(code: BrokerErrorCode, message: String) {
        self.code = code
        self.message = message
    }

    public var dto: BrokerErrorDTO { BrokerErrorDTO(code: code, message: message) }
}

/// Everything `CaptureBroker` needs from window/application discovery,
/// narrowed to exactly the two read-only calls WP6 uses. Kept separate from
/// `WindowCaptureService` itself (which is `@MainActor`) so the broker actor
/// can depend on a plain `Sendable` protocol instead of hopping actors
/// implicitly, and so tests can inject fixtures without ScreenCaptureKit or
/// screen-recording permission.
public protocol CaptureBrokerDiscovering: Sendable {
    func discoverApplications() async throws -> [ApplicationDescriptor]
    func discoverWindows() async throws -> [WindowDescriptor]
}

/// Production adapter over the real `WindowCaptureService` (WP2). Each call
/// hops onto `@MainActor` for the duration of one discovery snapshot, same
/// as every other caller of that service; no live `SCWindow`/`SCShareableContent`
/// crosses back out.
public struct LiveCaptureBrokerDiscovery: CaptureBrokerDiscovering {
    public init() {}

    public func discoverApplications() async throws -> [ApplicationDescriptor] {
        try await WindowCaptureService.shared.discoverApplications()
    }

    public func discoverWindows() async throws -> [WindowDescriptor] {
        try await WindowCaptureService.shared.discoverWindows()
    }
}

/// Everything `CaptureBroker` needs to answer `permissionsStatus`, narrowed
/// to two booleans so tests can inject fixed values instead of depending on
/// real TCC state.
public protocol CaptureBrokerPermissionsChecking: Sendable {
    func screenCaptureGranted() -> Bool
    func accessibilityGranted() -> Bool
}

/// Production adapter over the same preflight-only (non-prompting) APIs
/// already used elsewhere in the GUI
/// (`AccessibilityManager.isAccessibilityGranted`,
/// `BerryShotApp.swift`'s `CGPreflightScreenCaptureAccess()` check). Calling
/// these does not trigger a permission prompt.
public struct LiveCaptureBrokerPermissions: CaptureBrokerPermissionsChecking {
    public init() {}

    public func screenCaptureGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
}

/// Strips control characters and bounds length before a title/name crosses
/// the IPC boundary (`05-mcp-server-contract.md` section 3: "Titles must be
/// length-bounded and sanitized for control characters."). A free function
/// on a caseless enum so it is directly unit-testable without constructing
/// a broker.
public enum BrokerTextSanitizer {
    public static func sanitize(_ text: String, maxLength: Int = 500) -> String {
        let allowedScalars = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(allowedScalars))
        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength))
    }
}

/// GUI-side actor that is the single point of entry for every broker
/// operation. Owns a bounded FIFO queue so `BrokerIPCServer` can accept
/// concurrent connections while capture/discovery work is still serialized
/// and rate-limited (`02-target-architecture.md` section 3: "`CaptureBroker`
/// is an `actor` and owns one bounded capture queue").
///
/// WP6 only wires read-only, fast discovery operations through this queue;
/// the same queue is designed to carry WP7's capture operations later
/// without a redesign.
public actor CaptureBroker {
    private struct QueueEntry {
        let requestID: UUID
        let operation: BrokerOperation
        let deadline: Date
        let continuation: CheckedContinuation<BrokerResult, Error>
    }

    private let discovery: any CaptureBrokerDiscovering
    private let permissions: any CaptureBrokerPermissionsChecking
    /// WP7: performs the actual capture/OCR/redact/store pipeline for
    /// `captureWindow`. Defaults to a live implementation backed by
    /// `artifactStore`; tests inject a fake to exercise
    /// `performCaptureWindow`'s validation/error-mapping without real
    /// ScreenCaptureKit/Vision/AX.
    private let captureOperations: any CaptureBrokerCaptureOperating
    /// One store shared by every capture/resource operation this broker
    /// instance executes, so TTL/quota/lease bookkeeping stays consistent
    /// across calls instead of resetting per capture.
    private let artifactStore: CaptureArtifactStore
    private let ownBundleIdentifier: String?
    public let maxQueueDepth: Int

    /// WP8: session allowlist/mode/TTL/artifact-limit/redaction-policy
    /// bookkeeping (`06-agent-documentation-security.md` section 2).
    private let sessionManager: DocumentationSessionManager
    /// WP8: bounded safe AX snapshot serialization and guarded action
    /// execution (`06-agent-documentation-security.md` section 4).
    private let axInspecting: any AXInspecting
    /// WP8: opaque short-lived element refs bound to session/PID/generation.
    private let elementRegistry: UIElementRegistry
    /// WP8: `launch_application`/`activate_application`
    /// (`06-agent-documentation-security.md` section 4).
    private let applicationLaunching: any ApplicationLaunching

    private var queue: [QueueEntry] = []
    private var isDraining = false
    /// Request IDs cancelled while queued (removed immediately) or while
    /// executing (checked again when the operation finishes, so a
    /// cancel-then-finish race still surfaces as cancelled to the caller).
    private var cancelledRequestIDs: Set<UUID> = []

    public init(
        discovery: any CaptureBrokerDiscovering,
        permissions: any CaptureBrokerPermissionsChecking = LiveCaptureBrokerPermissions(),
        artifactStore: CaptureArtifactStore = CaptureArtifactStore(),
        captureOperations: (any CaptureBrokerCaptureOperating)? = nil,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        maxQueueDepth: Int = IPCProtocol.maxQueueDepth,
        sessionManager: DocumentationSessionManager = DocumentationSessionManager(),
        axInspecting: any AXInspecting = LiveAXInspecting(),
        elementRegistry: UIElementRegistry = UIElementRegistry(),
        applicationLaunching: any ApplicationLaunching = LiveApplicationLaunching()
    ) {
        self.discovery = discovery
        self.permissions = permissions
        self.artifactStore = artifactStore
        self.captureOperations = captureOperations ?? LiveCaptureBrokerCaptureOperations(store: artifactStore)
        self.ownBundleIdentifier = ownBundleIdentifier
        self.maxQueueDepth = maxQueueDepth
        self.sessionManager = sessionManager
        self.axInspecting = axInspecting
        self.elementRegistry = elementRegistry
        self.applicationLaunching = applicationLaunching
    }

    /// Enqueues `operation` and suspends until it is drained and executed,
    /// cancelled, or its deadline passes while still queued.
    ///
    /// `.cancel` and `.documentationSessionEnd` are both special-cased to
    /// run immediately instead of being enqueued: they are control-plane
    /// actions, not units of queued work, and their entire purpose is to
    /// reach a request that may be stuck behind a slow head-of-queue
    /// operation — for `.documentationSessionEnd` specifically, a long-running
    /// `wait_for_ui` sitting at the head of this exact queue
    /// (`06-agent-documentation-security.md` section 8: "Stop button
    /// cancels current wait/capture"). `wait_for_ui`'s own poll loop reads
    /// `DocumentationSessionManager`'s Stop flag directly (a different
    /// actor from this one), so ending the session out of band here still
    /// reaches it promptly even while this queue's `execute(_:)` call for
    /// the in-flight wait has not returned yet. Queueing `.documentationSessionEnd`
    /// behind that same wait would make it unable to ever interrupt exactly
    /// the case it exists for.
    ///
    /// - Throws: ``BrokerOperationError`` with `.rateLimited` if the queue
    ///   is already at ``maxQueueDepth``.
    public func submit(_ operation: BrokerOperation, requestID: UUID, deadline: Date) async throws -> BrokerResult {
        if case .cancel(let targetID) = operation {
            cancel(requestID: targetID)
            return .cancelAcknowledged
        }
        if case .documentationSessionEnd(let request) = operation {
            return try await performDocumentationSessionEnd(request)
        }
        guard queue.count < maxQueueDepth else {
            throw BrokerOperationError(code: .rateLimited, message: "Too many pending broker requests")
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.append(QueueEntry(requestID: requestID, operation: operation, deadline: deadline, continuation: continuation))
            kickDrainIfNeeded()
        }
    }

    /// Best-effort cancellation. If `requestID` is still queued it is
    /// removed and its waiter is resumed with `.cancelled` immediately; if
    /// it is currently executing (or has not been submitted at all, e.g. a
    /// stale/duplicate cancel), the ID is simply remembered so a
    /// still-in-flight result is discarded as cancelled once it completes.
    public func cancel(requestID: UUID) {
        if let index = queue.firstIndex(where: { $0.requestID == requestID }) {
            let entry = queue.remove(at: index)
            entry.continuation.resume(throwing: BrokerOperationError(code: .cancelled, message: "Cancelled"))
        } else {
            cancelledRequestIDs.insert(requestID)
        }
    }

    /// Cancels every queued request. Called when the broker/IPC server is
    /// stopped (Privacy setting disabled, GUI quitting) so no connection is
    /// left waiting on a continuation that will never resume
    /// (`08-implementation-work-packages.md` WP6 verification: "Stop/revoke
    /// closes clients and cancels queue").
    public func cancelAll() {
        let pending = queue
        queue.removeAll()
        for entry in pending {
            entry.continuation.resume(throwing: BrokerOperationError(code: .cancelled, message: "Broker stopped"))
        }
        // WP8: the global Stop control also ends every active documentation
        // session (`06-agent-documentation-security.md` section 6: "One-click
        // Stop revokes session token, cancels queue, closes IPC clients, and
        // removes ephemeral artifacts according to policy"). A `wait_for_ui`
        // call still executing (not queued — the drain loop already dequeued
        // it) notices via its own per-tick `sessionManager.isStopRequested`
        // poll rather than through this queue-cancellation path.
        Task { await sessionManager.stopAll() }
    }

    /// Current queue depth. Exposed only for tests.
    public var queuedCount: Int { queue.count }

    private func kickDrainIfNeeded() {
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    private func drain() async {
        while true {
            guard !queue.isEmpty else {
                isDraining = false
                return
            }
            let entry = queue.removeFirst()

            if cancelledRequestIDs.remove(entry.requestID) != nil {
                entry.continuation.resume(throwing: BrokerOperationError(code: .cancelled, message: "Cancelled"))
                continue
            }
            if Date() >= entry.deadline {
                entry.continuation.resume(throwing: BrokerOperationError(code: .deadlineExceeded, message: "Deadline exceeded before the request was processed"))
                continue
            }

            do {
                let result = try await execute(entry.operation)
                if cancelledRequestIDs.remove(entry.requestID) != nil {
                    entry.continuation.resume(throwing: BrokerOperationError(code: .cancelled, message: "Cancelled"))
                } else {
                    entry.continuation.resume(returning: result)
                }
            } catch let error as BrokerOperationError {
                entry.continuation.resume(throwing: error)
            } catch is CancellationError {
                entry.continuation.resume(throwing: BrokerOperationError(code: .cancelled, message: "Cancelled"))
            } catch {
                entry.continuation.resume(throwing: BrokerOperationError(code: .internalError, message: "Internal error"))
            }
        }
    }

    private func execute(_ operation: BrokerOperation) async throws -> BrokerResult {
        switch operation {
        case .ping:
            return .pong
        case .permissionsStatus:
            return .permissionsStatus(currentPermissionsStatus())
        case .listApplications(let request):
            return try await performListApplications(request)
        case .listWindows(let request):
            return try await performListWindows(request)
        case .captureWindow(let request):
            return try await performCaptureWindow(request)
        case .getCaptureManifest(let request):
            return try await performGetCaptureManifest(request)
        case .resolveArtifactResource(let request):
            return try await performResolveArtifactResource(request)
        case .documentationSessionBegin(let request):
            return try await performDocumentationSessionBegin(request)
        case .documentationSessionStatus(let request):
            return try await performDocumentationSessionStatus(request)
        case .documentationSessionCaptureStep(let request):
            return try await performDocumentationSessionCaptureStep(request)
        case .documentationSessionEnd(let request):
            // Unreachable in practice: `submit(_:requestID:deadline:)`
            // intercepts `.documentationSessionEnd` before it is ever
            // enqueued (see its doc comment). Handled here too so this
            // switch stays exhaustive and behaves correctly even if a
            // future caller reaches `execute` some other way.
            return try await performDocumentationSessionEnd(request)
        case .launchApplication(let request):
            return try await performLaunchApplication(request)
        case .activateApplication(let request):
            return try await performActivateApplication(request)
        case .inspectUI(let request):
            return try await performInspectUI(request)
        case .performUIAction(let request):
            return try await performPerformUIAction(request)
        case .waitForUI(let request):
            return try await performWaitForUI(request)
        case .cancel(let targetID):
            // Unreachable in practice: `submit(_:requestID:deadline:)`
            // intercepts `.cancel` before it is ever enqueued (see its doc
            // comment). Handled here too so this switch stays exhaustive
            // and behaves correctly even if a future caller reaches
            // `execute` some other way.
            cancel(requestID: targetID)
            return .cancelAcknowledged
        }
    }

    private func currentPermissionsStatus() -> PermissionsStatusDTO {
        PermissionsStatusDTO(
            screenCapture: permissions.screenCaptureGranted() ? .granted : .denied,
            accessibility: permissions.accessibilityGranted() ? .granted : .denied,
            berryshotRunning: true,
            brokerProtocolVersion: IPCProtocol.currentVersion
        )
    }

    private func performListApplications(_ request: ListApplicationsRequest) async throws -> BrokerResult {
        guard request.limit >= 1, request.limit <= 100 else {
            throw BrokerOperationError(code: .invalidArgument, message: "limit must be between 1 and 100")
        }
        if let query = request.query, query.count > 200 {
            throw BrokerOperationError(code: .invalidArgument, message: "query must be at most 200 characters")
        }
        let offset = try parseCursor(request.cursor)
        let all = try await discovery.discoverApplications()

        let filtered: [ApplicationDescriptor]
        if let query = request.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            let needle = query.lowercased()
            filtered = all.filter { $0.applicationName.lowercased().contains(needle) || $0.id.lowercased().contains(needle) }
        } else {
            filtered = all
        }

        guard offset <= filtered.count else {
            throw BrokerOperationError(code: .invalidArgument, message: "cursor out of range")
        }
        let page = filtered[offset...].prefix(request.limit)
        let nextOffset = offset + page.count
        let nextCursor = nextOffset < filtered.count ? String(nextOffset) : nil

        let dtos = page.map {
            ApplicationSummaryDTO(
                id: $0.id,
                applicationName: BrokerTextSanitizer.sanitize($0.applicationName),
                processID: $0.processID,
                isFrontmost: $0.isFrontmost,
                windowCount: $0.windowCount
            )
        }
        return .applications(ListApplicationsResult(applications: Array(dtos), nextCursor: nextCursor))
    }

    private func performListWindows(_ request: ListWindowsRequest) async throws -> BrokerResult {
        let bundleIdentifier = request.bundleIdentifier
        guard !bundleIdentifier.isEmpty, bundleIdentifier.count <= 255 else {
            throw BrokerOperationError(code: .invalidArgument, message: "bundle_id is required and must be at most 255 characters")
        }
        guard request.limit >= 1, request.limit <= 100 else {
            throw BrokerOperationError(code: .invalidArgument, message: "limit must be between 1 and 100")
        }
        let offset = try parseCursor(request.cursor)
        let allWindows = try await discovery.discoverWindows()
        let matching = ApplicationWindowDiscovery.windows(for: bundleIdentifier, in: allWindows)

        guard !matching.isEmpty else {
            throw BrokerOperationError(code: .applicationNotFound, message: "No eligible on-screen windows for this application")
        }
        guard offset <= matching.count else {
            throw BrokerOperationError(code: .invalidArgument, message: "cursor out of range")
        }
        let page = matching[offset...].prefix(request.limit)
        let nextOffset = offset + page.count
        let nextCursor = nextOffset < matching.count ? String(nextOffset) : nil

        let dtos = page.map {
            WindowSummaryDTO(
                id: $0.id,
                bundleIdentifier: $0.bundleIdentifier,
                applicationName: BrokerTextSanitizer.sanitize($0.applicationName),
                processID: $0.processID,
                title: BrokerTextSanitizer.sanitize($0.title),
                isOnScreen: $0.isOnScreen,
                isFrontmost: $0.isFrontmost
            )
        }
        return .windows(ListWindowsResult(windows: Array(dtos), nextCursor: nextCursor))
    }

    // MARK: - captureWindow / getCaptureManifest / resolveArtifactResource (WP7)

    /// Validates bounds, re-resolves the requested window from a fresh
    /// discovery snapshot, and verifies its bundle identity immediately
    /// before capture (`05-mcp-server-contract.md` section 3: "The broker
    /// must verify the current window still belongs to `expected_bundle_id`
    /// immediately before capture") — the same staleness/identity contract
    /// `WindowCaptureService.captureWindow` itself enforces a second time
    /// (defense in depth against a window closing between this lookup and
    /// the actual `SCScreenshotManager` call a moment later).
    private func performCaptureWindow(_ request: CaptureWindowRequest) async throws -> BrokerResult {
        guard !request.expectedBundleIdentifier.isEmpty, request.expectedBundleIdentifier.count <= 255 else {
            throw BrokerOperationError(code: .invalidArgument, message: "expected_bundle_id is required and must be at most 255 characters")
        }
        guard request.previewMaxEdge >= 320, request.previewMaxEdge <= 1280 else {
            throw BrokerOperationError(code: .invalidArgument, message: "preview_max_edge must be between 320 and 1280")
        }
        guard permissions.screenCaptureGranted() else {
            throw BrokerOperationError(code: .permissionDenied, message: "Screen Recording permission is required to capture content")
        }

        let windows = try await discovery.discoverWindows()
        guard let matched = windows.first(where: { $0.id == request.windowID }) else {
            throw BrokerOperationError(code: .windowNotAvailable, message: "The requested window is not currently available")
        }
        guard matched.bundleIdentifier == request.expectedBundleIdentifier else {
            throw BrokerOperationError(code: .windowIdentityChanged, message: "The window no longer belongs to the expected application")
        }

        try Task.checkCancellation()
        let manifest = try await captureOperations.captureWindow(request, matchedWindow: matched)
        return .manifest(manifest)
    }

    private func performGetCaptureManifest(_ request: GetCaptureManifestRequest) async throws -> BrokerResult {
        do {
            let manifest = try await artifactStore.manifest(captureID: request.captureID)
            return .manifest(manifest)
        } catch {
            throw Self.mapArtifactStoreError(error)
        }
    }

    private func performResolveArtifactResource(_ request: ResolveArtifactResourceRequest) async throws -> BrokerResult {
        do {
            let location = try await artifactStore.resolve(captureID: request.captureID, kind: request.kind)
            return .artifactResource(location)
        } catch {
            throw Self.mapArtifactStoreError(error)
        }
    }

    private static func mapArtifactStoreError(_ error: Error) -> BrokerOperationError {
        guard let storeError = error as? CaptureArtifactStore.StoreError else {
            return BrokerOperationError(code: .internalError, message: "Internal error")
        }
        switch storeError {
        case .malformedID:
            return BrokerOperationError(code: .invalidArgument, message: "capture_id must be a valid UUID")
        case .notFound, .notPublished:
            return BrokerOperationError(code: .resourceNotFound, message: "Unknown capture resource")
        case .expired:
            return BrokerOperationError(code: .resourceExpired, message: "This capture has expired")
        case .writeFailed:
            return BrokerOperationError(code: .internalError, message: "Internal error")
        }
    }

    private func parseCursor(_ cursor: String?) throws -> Int {
        guard let cursor else { return 0 }
        guard let value = Int(cursor), value >= 0 else {
            throw BrokerOperationError(code: .invalidArgument, message: "Malformed cursor")
        }
        return value
    }

    // MARK: - WP8 documentation sessions (`06-agent-documentation-security.md` section 2)

    private static func mapSessionError(_ error: DocumentationSessionManager.SessionError) -> BrokerOperationError {
        switch error {
        case .invalidArgument(let message):
            return BrokerOperationError(code: .invalidArgument, message: message)
        case .notFound:
            return BrokerOperationError(code: .sessionNotFound, message: "Unknown documentation session")
        case .expired:
            return BrokerOperationError(code: .sessionExpired, message: "This documentation session has expired")
        case .stopped:
            return BrokerOperationError(code: .sessionStopped, message: "This documentation session has been stopped")
        case .artifactLimitReached:
            return BrokerOperationError(code: .artifactLimitReached, message: "This session's artifact limit has been reached")
        }
    }

    /// Every WP8 operation other than `begin` starts by resolving its
    /// session through here, so allowlist/TTL/Stop enforcement lives in
    /// exactly one place (`DocumentationSessionManager.activeSession(_:)`).
    private func resolveSession(_ sessionID: String) async throws -> DocumentationSessionManager.Session {
        do {
            return try await sessionManager.activeSession(sessionID)
        } catch let error as DocumentationSessionManager.SessionError {
            throw Self.mapSessionError(error)
        }
    }

    private func performDocumentationSessionBegin(_ request: DocumentationSessionBeginRequest) async throws -> BrokerResult {
        do {
            let dto = try await sessionManager.begin(request)
            DocumentationAuditLog.record(tool: "documentation_session_begin", sessionID: dto.sessionID, target: dto.bundleIdentifier, outcome: "success")
            return .documentationSession(dto)
        } catch let error as DocumentationSessionManager.SessionError {
            throw Self.mapSessionError(error)
        }
    }

    private func performDocumentationSessionStatus(_ request: DocumentationSessionStatusRequest) async throws -> BrokerResult {
        do {
            let dto = try await sessionManager.status(sessionID: request.sessionID)
            return .documentationSession(dto)
        } catch let error as DocumentationSessionManager.SessionError {
            throw Self.mapSessionError(error)
        }
    }

    /// Captures one window through the exact same pipeline `captureWindow`
    /// uses, but scoped entirely by the session: the target window's bundle
    /// identity is re-verified against `session.bundleIdentifier` (not a
    /// caller-supplied `expected_bundle_id`) immediately before capture —
    /// the WP8 analogue of `performCaptureWindow`'s own staleness/identity
    /// check — and redaction policy/style come from the session, never from
    /// this request (`06-agent-documentation-security.md` section 8:
    /// "Attempt action against a non-session bundle ID: rejected").
    private func performDocumentationSessionCaptureStep(_ request: DocumentationSessionCaptureStepRequest) async throws -> BrokerResult {
        let session = try await resolveSession(request.sessionID)
        guard !request.feature.isEmpty, request.feature.count <= DocumentationSessionManager.maxFeatureNameLength else {
            throw BrokerOperationError(code: .invalidArgument, message: "feature is required and must be at most \(DocumentationSessionManager.maxFeatureNameLength) characters")
        }
        guard permissions.screenCaptureGranted() else {
            throw BrokerOperationError(code: .permissionDenied, message: "Screen Recording permission is required to capture content")
        }

        let windows = try await discovery.discoverWindows()
        guard let matched = windows.first(where: { $0.id == request.windowID }) else {
            throw BrokerOperationError(code: .windowNotAvailable, message: "The requested window is not currently available")
        }
        guard matched.bundleIdentifier == session.bundleIdentifier else {
            DocumentationAuditLog.record(tool: "documentation_session_capture_step", sessionID: request.sessionID, target: matched.bundleIdentifier, outcome: "bundle_not_allowed")
            throw BrokerOperationError(code: .bundleNotAllowed, message: "The requested window does not belong to this session's allowlisted application")
        }

        try Task.checkCancellation()

        let captureRequest = CaptureWindowRequest(
            windowID: request.windowID,
            expectedBundleIdentifier: session.bundleIdentifier,
            redactionPolicy: session.redactionPolicy,
            redactionStyle: session.redactionStyle,
            ocr: request.ocr,
            previewMaxEdge: 960
        )
        let manifest = try await captureOperations.captureWindow(captureRequest, matchedWindow: matched)

        do {
            let updatedSession = try await sessionManager.recordStep(
                sessionID: request.sessionID,
                captureID: manifest.captureID,
                feature: request.feature,
                navigationSummary: request.navigationSummary,
                redactionStatus: manifest.redactionStatus,
                verification: request.verification,
                notes: request.notes
            )
            DocumentationAuditLog.record(tool: "documentation_session_capture_step", sessionID: request.sessionID, target: manifest.captureID, outcome: "success", redactionStatus: manifest.redactionStatus.rawValue)
            return .documentationSession(updatedSession)
        } catch let error as DocumentationSessionManager.SessionError {
            throw Self.mapSessionError(error)
        }
    }

    private func performDocumentationSessionEnd(_ request: DocumentationSessionEndRequest) async throws -> BrokerResult {
        do {
            let dto = try await sessionManager.end(sessionID: request.sessionID)
            await elementRegistry.clearSession(request.sessionID)
            DocumentationAuditLog.record(tool: "documentation_session_end", sessionID: request.sessionID, target: dto.bundleIdentifier, outcome: "stopped")
            return .documentationSession(dto)
        } catch let error as DocumentationSessionManager.SessionError {
            throw Self.mapSessionError(error)
        }
    }

    // MARK: - WP8 launch_application / activate_application

    private func performLaunchApplication(_ request: LaunchApplicationRequest) async throws -> BrokerResult {
        let session = try await resolveSession(request.sessionID)
        guard session.allowLaunch else {
            throw BrokerOperationError(code: .launchNotApproved, message: "This session was not created with allowLaunch: true")
        }
        guard request.approve else {
            throw BrokerOperationError(code: .launchNotApproved, message: "This call did not set approve: true")
        }

        let wasRunning = applicationLaunching.runningProcessID(bundleIdentifier: session.bundleIdentifier) != nil
        do {
            let pid = try await applicationLaunching.launch(bundleIdentifier: session.bundleIdentifier)
            await sessionManager.touchAction(sessionID: request.sessionID, description: "Launched application")
            DocumentationAuditLog.record(tool: "launch_application", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "success")
            return .applicationLaunch(ApplicationLaunchResultDTO(bundleIdentifier: session.bundleIdentifier, processID: pid, wasAlreadyRunning: wasRunning, isActive: true))
        } catch {
            DocumentationAuditLog.record(tool: "launch_application", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "failed")
            throw BrokerOperationError(code: .internalError, message: "Could not launch the application")
        }
    }

    private func performActivateApplication(_ request: ActivateApplicationRequest) async throws -> BrokerResult {
        let session = try await resolveSession(request.sessionID)
        guard let pid = applicationLaunching.runningProcessID(bundleIdentifier: session.bundleIdentifier) else {
            throw BrokerOperationError(code: .applicationNotRunning, message: "The session's application is not currently running")
        }
        let activated = applicationLaunching.activate(bundleIdentifier: session.bundleIdentifier)
        await sessionManager.touchAction(sessionID: request.sessionID, description: "Activated application")
        DocumentationAuditLog.record(tool: "activate_application", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: activated ? "success" : "not_active")
        return .applicationLaunch(ApplicationLaunchResultDTO(bundleIdentifier: session.bundleIdentifier, processID: pid, wasAlreadyRunning: true, isActive: activated))
    }

    // MARK: - WP8 inspect_ui / perform_ui_action / wait_for_ui

    private static let minInspectDepth = 1
    private static let maxInspectDepth = 12
    private static let minInspectNodes = 1
    private static let maxInspectNodes = 500
    private static let minWaitTimeoutMilliseconds = 100
    private static let maxWaitTimeoutMilliseconds = 15_000
    private static let waitPollIntervalNanoseconds: UInt64 = 150_000_000
    private static let waitSnapshotMaxDepth = 10
    private static let waitSnapshotMaxNodes = 300

    private func performInspectUI(_ request: InspectUIRequest) async throws -> BrokerResult {
        let session = try await resolveSession(request.sessionID)
        guard request.maxDepth >= Self.minInspectDepth, request.maxDepth <= Self.maxInspectDepth else {
            throw BrokerOperationError(code: .invalidArgument, message: "max_depth must be between \(Self.minInspectDepth) and \(Self.maxInspectDepth)")
        }
        guard request.maxNodes >= Self.minInspectNodes, request.maxNodes <= Self.maxInspectNodes else {
            throw BrokerOperationError(code: .invalidArgument, message: "max_nodes must be between \(Self.minInspectNodes) and \(Self.maxInspectNodes)")
        }
        guard let pid = applicationLaunching.runningProcessID(bundleIdentifier: session.bundleIdentifier) else {
            throw BrokerOperationError(code: .applicationNotRunning, message: "The session's application is not currently running")
        }

        var rootHandle: (any Sendable)?
        if let elementRef = request.elementRef {
            switch await elementRegistry.resolve(ref: elementRef, sessionID: request.sessionID, pid: pid) {
            case .success(let entry):
                rootHandle = entry.handle
            case .failure:
                throw BrokerOperationError(code: .elementStale, message: "The requested root element reference is no longer valid")
            }
        }

        let snapshot: AXInspectionSnapshot
        do {
            snapshot = try axInspecting.snapshot(pid: pid, root: rootHandle, maxDepth: request.maxDepth, maxNodes: request.maxNodes)
        } catch {
            throw BrokerOperationError(code: .applicationNotRunning, message: "Could not inspect the application's accessibility tree")
        }

        let generation = await elementRegistry.beginGeneration(sessionID: request.sessionID)
        let rootDTO = await elementRegistry.registerTree(snapshot.root, sessionID: request.sessionID, pid: pid, generation: generation)
        await sessionManager.touchAction(sessionID: request.sessionID, description: "Inspected UI")
        DocumentationAuditLog.record(tool: "inspect_ui", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "success")

        return .uiSnapshot(UISnapshotDTO(
            sessionID: request.sessionID,
            bundleIdentifier: session.bundleIdentifier,
            processID: pid,
            generation: generation,
            windowTitle: snapshot.windowTitle,
            root: rootDTO,
            truncatedByDepth: snapshot.truncatedByDepth,
            truncatedByNodeCount: snapshot.truncatedByNodeCount
        ))
    }

    /// The security-critical path: every guard here must reject *before*
    /// `axInspecting.performAction` is ever called
    /// (`06-agent-documentation-security.md` section 8's verification
    /// checklist maps directly onto these guards in order — stale ref,
    /// secure field, blocked/unsupported action).
    private func performPerformUIAction(_ request: PerformUIActionRequest) async throws -> BrokerResult {
        let session = try await resolveSession(request.sessionID)
        guard let pid = applicationLaunching.runningProcessID(bundleIdentifier: session.bundleIdentifier) else {
            throw BrokerOperationError(code: .applicationNotRunning, message: "The session's application is not currently running")
        }

        if request.action == .setValue {
            guard let value = request.value, value.count <= AXAutomationTextSanitizer.maxLength else {
                throw BrokerOperationError(code: .invalidArgument, message: "value is required for setValue and must be at most \(AXAutomationTextSanitizer.maxLength) characters")
            }
        } else if request.value != nil {
            throw BrokerOperationError(code: .invalidArgument, message: "value is only accepted for the setValue action")
        }

        let entry: UIElementRegistry.Entry
        switch await elementRegistry.resolve(ref: request.elementRef, sessionID: request.sessionID, pid: pid) {
        case .success(let resolved):
            entry = resolved
        case .failure:
            DocumentationAuditLog.record(tool: "perform_ui_action", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "element_stale")
            throw BrokerOperationError(code: .elementStale, message: "The requested element reference is no longer valid")
        }

        guard !SecureElementGuard.isSecure(role: entry.role, subrole: entry.subrole) else {
            DocumentationAuditLog.record(tool: "perform_ui_action", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "action_blocked_secure")
            throw BrokerOperationError(code: .actionBlocked, message: "This element is a secure field and cannot be acted on")
        }
        guard !DestructiveActionGuard.isBlocked(title: entry.title, description: entry.descriptionText) else {
            DocumentationAuditLog.record(tool: "perform_ui_action", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "action_blocked_destructive")
            throw BrokerOperationError(code: .actionBlocked, message: "This control is blocked by policy")
        }
        guard entry.advertisedActions.contains(request.action) else {
            DocumentationAuditLog.record(tool: "perform_ui_action", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "action_blocked_unsupported")
            throw BrokerOperationError(code: .actionBlocked, message: "This element does not support the requested action")
        }

        let performed: Bool
        do {
            performed = try axInspecting.performAction(pid: pid, handle: entry.handle, action: request.action, value: request.value)
        } catch {
            DocumentationAuditLog.record(tool: "perform_ui_action", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "action_failed")
            throw BrokerOperationError(code: .actionBlocked, message: "The action could not be performed")
        }

        await sessionManager.touchAction(sessionID: request.sessionID, description: "Performed \(request.action.rawValue)")
        DocumentationAuditLog.record(tool: "perform_ui_action", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: performed ? "success" : "not_performed")
        return .uiActionResult(UIActionResultDTO(sessionID: request.sessionID, elementRef: request.elementRef, action: request.action, performed: performed, role: entry.role))
    }

    /// Bounded backoff polling that only ever runs for the duration of this
    /// one awaited call (`06-agent-documentation-security.md` section 4:
    /// "Hard timeout and cancellation are required... No infinite/background
    /// polling"). Checks `Task` cancellation and the session's Stop flag on
    /// every tick — not only at entry — so a Stop invoked mid-wait ends this
    /// call within one poll interval instead of running to the full
    /// timeout (section 8: "Stop button cancels current wait/capture").
    private func performWaitForUI(_ request: WaitForUIRequest) async throws -> BrokerResult {
        let session = try await resolveSession(request.sessionID)
        guard request.timeoutMilliseconds >= Self.minWaitTimeoutMilliseconds, request.timeoutMilliseconds <= Self.maxWaitTimeoutMilliseconds else {
            throw BrokerOperationError(code: .invalidArgument, message: "timeout_ms must be between \(Self.minWaitTimeoutMilliseconds) and \(Self.maxWaitTimeoutMilliseconds)")
        }
        switch request.predicate {
        case .enabledStateEquals, .focusedStateEquals:
            guard request.elementRef != nil, request.expectedBool != nil else {
                throw BrokerOperationError(code: .invalidArgument, message: "element_ref and expected_bool are required for this predicate")
            }
        case .elementAppears, .elementDisappears:
            guard (request.roleQuery?.isEmpty == false) || (request.titleQuery?.isEmpty == false) else {
                throw BrokerOperationError(code: .invalidArgument, message: "role_query or title_query is required for this predicate")
            }
        case .windowTitleContains:
            guard request.titleQuery?.isEmpty == false else {
                throw BrokerOperationError(code: .invalidArgument, message: "title_query is required for this predicate")
            }
        }
        guard let pid = applicationLaunching.runningProcessID(bundleIdentifier: session.bundleIdentifier) else {
            throw BrokerOperationError(code: .applicationNotRunning, message: "The session's application is not currently running")
        }

        let start = Date()
        let deadline = start.addingTimeInterval(TimeInterval(request.timeoutMilliseconds) / 1000)

        while true {
            try Task.checkCancellation()
            if await sessionManager.isStopRequested(request.sessionID) {
                DocumentationAuditLog.record(tool: "wait_for_ui", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "stopped")
                throw BrokerOperationError(code: .cancelled, message: "The documentation session was stopped")
            }

            if try await evaluateWaitPredicate(request, sessionID: request.sessionID, pid: pid) {
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                await sessionManager.touchAction(sessionID: request.sessionID, description: "Wait satisfied: \(request.predicate.rawValue)")
                DocumentationAuditLog.record(tool: "wait_for_ui", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "satisfied")
                return .uiWaitResult(UIWaitResultDTO(sessionID: request.sessionID, satisfied: true, timedOut: false, elapsedMilliseconds: elapsed))
            }

            if Date() >= deadline {
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                DocumentationAuditLog.record(tool: "wait_for_ui", sessionID: request.sessionID, target: session.bundleIdentifier, outcome: "timed_out")
                return .uiWaitResult(UIWaitResultDTO(sessionID: request.sessionID, satisfied: false, timedOut: true, elapsedMilliseconds: elapsed))
            }

            try? await Task.sleep(nanoseconds: Self.waitPollIntervalNanoseconds)
        }
    }

    private func evaluateWaitPredicate(_ request: WaitForUIRequest, sessionID: String, pid: Int32) async throws -> Bool {
        switch request.predicate {
        case .enabledStateEquals, .focusedStateEquals:
            guard let ref = request.elementRef, let expected = request.expectedBool else { return false }
            guard case .success(let entry) = await elementRegistry.resolve(ref: ref, sessionID: sessionID, pid: pid) else {
                throw BrokerOperationError(code: .elementStale, message: "The requested element reference is no longer valid")
            }
            guard let state = axInspecting.currentState(pid: pid, handle: entry.handle) else { return false }
            return request.predicate == .enabledStateEquals ? state.enabled == expected : state.focused == expected

        case .elementAppears, .elementDisappears, .windowTitleContains:
            let snapshot: AXInspectionSnapshot
            do {
                snapshot = try axInspecting.snapshot(pid: pid, root: nil, maxDepth: Self.waitSnapshotMaxDepth, maxNodes: Self.waitSnapshotMaxNodes)
            } catch {
                // The application may be transiently unavailable mid-wait
                // (e.g. between windows); keep polling until the deadline
                // rather than failing the whole call on one bad tick.
                return false
            }
            if request.predicate == .windowTitleContains {
                guard let query = request.titleQuery else { return false }
                return snapshot.windowTitle.localizedCaseInsensitiveContains(query)
            }
            let found = Self.findNode(in: snapshot.root, roleQuery: request.roleQuery, titleQuery: request.titleQuery)
            return request.predicate == .elementAppears ? found : !found
        }
    }

    private static func findNode(in node: AXObservedNode, roleQuery: String?, titleQuery: String?) -> Bool {
        let roleMatches = roleQuery.map { $0 == node.role } ?? true
        let titleMatches = titleQuery.map { (node.title ?? "").localizedCaseInsensitiveContains($0) } ?? true
        if roleMatches, titleMatches, roleQuery != nil || titleQuery != nil {
            return true
        }
        return node.children.contains { findNode(in: $0, roleQuery: roleQuery, titleQuery: titleQuery) }
    }
}
