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
    private let ownBundleIdentifier: String?
    public let maxQueueDepth: Int

    private var queue: [QueueEntry] = []
    private var isDraining = false
    /// Request IDs cancelled while queued (removed immediately) or while
    /// executing (checked again when the operation finishes, so a
    /// cancel-then-finish race still surfaces as cancelled to the caller).
    private var cancelledRequestIDs: Set<UUID> = []

    public init(
        discovery: any CaptureBrokerDiscovering,
        permissions: any CaptureBrokerPermissionsChecking = LiveCaptureBrokerPermissions(),
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        maxQueueDepth: Int = IPCProtocol.maxQueueDepth
    ) {
        self.discovery = discovery
        self.permissions = permissions
        self.ownBundleIdentifier = ownBundleIdentifier
        self.maxQueueDepth = maxQueueDepth
    }

    /// Enqueues `operation` and suspends until it is drained and executed,
    /// cancelled, or its deadline passes while still queued.
    ///
    /// `.cancel` is special-cased to run immediately instead of being
    /// enqueued: it is a control-plane action, not a unit of queued work,
    /// and its entire purpose is to reach a request that may be stuck
    /// behind a slow head-of-queue operation. Queueing it behind that same
    /// operation would make it unable to ever cancel exactly the case it
    /// exists for.
    ///
    /// - Throws: ``BrokerOperationError`` with `.rateLimited` if the queue
    ///   is already at ``maxQueueDepth``.
    public func submit(_ operation: BrokerOperation, requestID: UUID, deadline: Date) async throws -> BrokerResult {
        if case .cancel(let targetID) = operation {
            cancel(requestID: targetID)
            return .cancelAcknowledged
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

    private func parseCursor(_ cursor: String?) throws -> Int {
        guard let cursor else { return 0 }
        guard let value = Int(cursor), value >= 0 else {
            throw BrokerOperationError(code: .invalidArgument, message: "Malformed cursor")
        }
        return value
    }
}
