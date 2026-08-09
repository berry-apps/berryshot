import Foundation
@testable import BerryShot
import BerryShotIPC

/// A deterministic fake AX tree node used only by tests. `id` doubles as the
/// opaque test "handle" `FakeAXInspecting` hands back through
/// `AXObservedNode.handle` — a plain `String`, never a real `AXUIElement` —
/// so WP8's security-matrix tests can drive `CaptureBroker`'s guard logic
/// without Accessibility permission or a real GUI process, exactly like
/// WP6/WP7's `FakeDiscovery`/fake capture pipeline avoid ScreenCaptureKit.
struct FakeAXNode {
    let id: String
    let role: String
    var subrole: String?
    var title: String?
    var descriptionText: String?
    var enabledState: Bool = true
    var focused: Bool = false
    /// What this fake's AX layer would truthfully report as supported —
    /// `FakeAXInspecting` still runs the exact same secure/destructive/
    /// role-eligibility guards production code runs before ever honoring
    /// these.
    var realActions: [UIActionKind] = []
    var children: [FakeAXNode] = []
}

/// Test double for `AXInspecting`. `@unchecked Sendable` + `NSLock`: tests
/// need to mutate state (toggle `enabled`/`focused`, mark an app
/// unavailable) from a different `Task` than the one driving
/// `CaptureBroker`'s `wait_for_ui` poll loop, the same pattern
/// `BrokerIPCServer`/`ResponseBox` already use for cross-thread test state.
final class FakeAXInspecting: AXInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var windows: [Int32: FakeAXNode] = [:]
    private var windowTitles: [Int32: String] = [:]
    private var nodesByID: [String: FakeAXNode] = [:]
    private var enabledOverrides: [String: Bool] = [:]
    private var focusedOverrides: [String: Bool] = [:]
    private var unavailablePIDs: Set<Int32> = []
    private var recordedActions: [(id: String, action: UIActionKind, value: String?)] = []

    func setWindow(pid: Int32, title: String, root: FakeAXNode) {
        lock.lock(); defer { lock.unlock() }
        windows[pid] = root
        windowTitles[pid] = title
        index(root)
    }

    private func index(_ node: FakeAXNode) {
        nodesByID[node.id] = node
        for child in node.children { index(child) }
    }

    func setUnavailable(pid: Int32) {
        lock.lock(); defer { lock.unlock() }
        unavailablePIDs.insert(pid)
    }

    func setEnabled(_ enabled: Bool, forID id: String) {
        lock.lock(); defer { lock.unlock() }
        enabledOverrides[id] = enabled
    }

    func setFocused(_ focused: Bool, forID id: String) {
        lock.lock(); defer { lock.unlock() }
        focusedOverrides[id] = focused
    }

    /// Removes a node (and its subtree) from the fake window so
    /// `elementAppears`/`elementDisappears` waits have something to react
    /// to. No-op if the id is not present.
    func removeNode(id: String, fromPID pid: Int32) {
        lock.lock(); defer { lock.unlock() }
        guard var root = windows[pid] else { return }
        root = Self.removing(id: id, from: root)
        windows[pid] = root
        nodesByID.removeValue(forKey: id)
    }

    private static func removing(id: String, from node: FakeAXNode) -> FakeAXNode {
        var copy = node
        copy.children = node.children.filter { $0.id != id }.map { removing(id: id, from: $0) }
        return copy
    }

    func actionsPerformed() -> [(id: String, action: UIActionKind, value: String?)] {
        lock.lock(); defer { lock.unlock() }
        return recordedActions
    }

    // MARK: - AXInspecting

    func snapshot(pid: pid_t, root: (any Sendable)?, maxDepth: Int, maxNodes: Int) throws -> AXInspectionSnapshot {
        lock.lock(); defer { lock.unlock() }
        if unavailablePIDs.contains(pid) { throw AXInspectionError.applicationNotAvailable }
        let rootNode: FakeAXNode
        if let handleID = root as? String {
            guard let node = nodesByID[handleID] else { throw AXInspectionError.elementNotAvailable }
            rootNode = node
        } else if let node = windows[pid] {
            rootNode = node
        } else {
            throw AXInspectionError.noFocusedWindow
        }

        var count = 0
        var truncatedByDepth = false
        var truncatedByNodeCount = false
        let observed = convert(rootNode, depth: 0, maxDepth: maxDepth, maxNodes: maxNodes, count: &count, truncatedByDepth: &truncatedByDepth, truncatedByNodeCount: &truncatedByNodeCount)
        return AXInspectionSnapshot(windowTitle: windowTitles[pid] ?? "", root: observed, truncatedByDepth: truncatedByDepth, truncatedByNodeCount: truncatedByNodeCount)
    }

    private func convert(_ node: FakeAXNode, depth: Int, maxDepth: Int, maxNodes: Int, count: inout Int, truncatedByDepth: inout Bool, truncatedByNodeCount: inout Bool) -> AXObservedNode {
        count += 1
        let enabled = enabledOverrides[node.id] ?? node.enabledState
        let focused = focusedOverrides[node.id] ?? node.focused

        var children: [AXObservedNode] = []
        if depth + 1 > maxDepth {
            if !node.children.isEmpty { truncatedByDepth = true }
        } else {
            for child in node.children {
                if count >= maxNodes {
                    truncatedByNodeCount = true
                    break
                }
                children.append(convert(child, depth: depth + 1, maxDepth: maxDepth, maxNodes: maxNodes, count: &count, truncatedByDepth: &truncatedByDepth, truncatedByNodeCount: &truncatedByNodeCount))
            }
        }

        // Mirrors `LiveAXInspecting.walk`'s own secure/destructive filtering
        // exactly: a secure or destructive-by-title fake node must never
        // advertise any action in the snapshot, regardless of what
        // `realActions` claims the underlying (fake) AX layer supports —
        // otherwise this fixture would understate the real production
        // behavior it stands in for and give the security-matrix tests a
        // false sense of coverage.
        let isSecure = SecureElementGuard.isSecure(role: node.role, subrole: node.subrole)
        let isBlocked = DestructiveActionGuard.isBlocked(title: node.title, description: node.descriptionText)
        let advertisedActions = (isSecure || isBlocked) ? [] : node.realActions

        return AXObservedNode(
            handle: node.id,
            role: node.role,
            subrole: node.subrole,
            title: node.title,
            descriptionText: node.descriptionText,
            enabledState: enabled,
            focused: focused,
            frame: nil,
            supportedActions: advertisedActions,
            childCount: node.children.count,
            children: children
        )
    }

    func performAction(pid: pid_t, handle: any Sendable, action: UIActionKind, value: String?) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let id = handle as? String, let node = nodesByID[id] else { throw AXInspectionError.elementNotAvailable }
        guard !SecureElementGuard.isSecure(role: node.role, subrole: node.subrole) else { throw AXInspectionError.actionBlocked }
        guard !DestructiveActionGuard.isBlocked(title: node.title, description: node.descriptionText) else { throw AXInspectionError.actionBlocked }
        guard node.realActions.contains(action) else { throw AXInspectionError.actionBlocked }
        recordedActions.append((id: id, action: action, value: value))
        return true
    }

    func currentState(pid: pid_t, handle: any Sendable) -> (enabled: Bool, focused: Bool)? {
        lock.lock(); defer { lock.unlock() }
        guard let id = handle as? String, let node = nodesByID[id] else { return nil }
        return (enabledOverrides[id] ?? node.enabledState, focusedOverrides[id] ?? node.focused)
    }
}

/// Test double for `ApplicationLaunching`. `@unchecked Sendable` + `NSLock`
/// for the same cross-`Task` mutation reason as `FakeAXInspecting`.
final class FakeApplicationLaunching: ApplicationLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var runningPIDs: [String: Int32] = [:]
    private var nextSyntheticPID: Int32 = 9000
    var launchShouldFail = false
    private var launchCount = 0
    private var activateCount = 0

    func setRunning(bundleIdentifier: String, pid: Int32) {
        lock.lock(); defer { lock.unlock() }
        runningPIDs[bundleIdentifier] = pid
    }

    func setNotRunning(bundleIdentifier: String) {
        lock.lock(); defer { lock.unlock() }
        runningPIDs.removeValue(forKey: bundleIdentifier)
    }

    func launchCallCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return launchCount
    }

    func activateCallCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return activateCount
    }

    func runningProcessID(bundleIdentifier: String) -> Int32? {
        lock.lock(); defer { lock.unlock() }
        return runningPIDs[bundleIdentifier]
    }

    private enum LaunchOutcome {
        case existing(Int32)
        case shouldFail
        case launched(Int32)
    }

    func launch(bundleIdentifier: String) async throws -> Int32 {
        // The actual lock()/unlock() pair is isolated in a synchronous,
        // non-async helper: Swift 6 strict concurrency disallows calling
        // `NSLock.lock()`/`unlock()` directly inside an `async` function
        // body (even with no `await` between them), so the locked section
        // is factored into `performLaunch`, called synchronously from here.
        switch performLaunch(bundleIdentifier: bundleIdentifier) {
        case .existing(let pid), .launched(let pid):
            return pid
        case .shouldFail:
            throw ApplicationLaunchingError.launchFailed
        }
    }

    private func performLaunch(bundleIdentifier: String) -> LaunchOutcome {
        lock.lock(); defer { lock.unlock() }
        launchCount += 1
        if let existing = runningPIDs[bundleIdentifier] {
            return .existing(existing)
        }
        if launchShouldFail {
            return .shouldFail
        }
        let pid = nextSyntheticPID
        nextSyntheticPID += 1
        runningPIDs[bundleIdentifier] = pid
        return .launched(pid)
    }

    func activate(bundleIdentifier: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        activateCount += 1
        return runningPIDs[bundleIdentifier] != nil
    }
}

/// A trivial thread-safe mutable box, used to feed
/// `DocumentationSessionManager`'s injectable `clock` closure a value tests
/// can fast-forward deterministically instead of sleeping in wall-clock
/// time to exercise TTL expiry.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) { stored = value }

    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

/// Shared session-begin request builder so security-matrix tests do not
/// each re-type every bound.
func makeSessionBeginRequest(
    bundleIdentifier: String = "com.example.SafeApp",
    displayName: String = "Test session",
    mode: DocumentationSessionMode = .interactive,
    ttlSeconds: Int = 1800,
    maxArtifacts: Int = 20,
    allowLaunch: Bool = false
) -> DocumentationSessionBeginRequest {
    DocumentationSessionBeginRequest(
        bundleIdentifier: bundleIdentifier,
        displayName: displayName,
        mode: mode,
        redactionPolicy: nil,
        redactionStyle: .solid,
        ttlSeconds: ttlSeconds,
        maxArtifacts: maxArtifacts,
        allowLaunch: allowLaunch
    )
}

/// A "sample safe app" fixture: a well-behaved window exposing three
/// distinct navigable functions (a settings toggle, a search field, and a
/// save button) plus one secure field and one destructive-by-title button —
/// enough surface for both the coverage-completeness test
/// (`08-implementation-work-packages.md` WP8 verification: "A sample safe
/// app can be navigated through at least three functions") and the
/// secure/destructive security-matrix tests.
func makeSampleSafeAppWindow() -> FakeAXNode {
    FakeAXNode(
        id: "root-window",
        role: "AXWindow",
        title: "Sample Safe App",
        children: [
            FakeAXNode(id: "settings-toggle", role: "AXCheckBox", title: "Enable Notifications", realActions: [.press]),
            FakeAXNode(id: "search-field", role: "AXTextField", title: "Search", realActions: [.press, .setValue]),
            FakeAXNode(id: "save-button", role: "AXButton", title: "Save", realActions: [.press]),
            FakeAXNode(id: "password-field", role: "AXTextField", subrole: "AXSecureTextField", title: "Password", realActions: [.press, .setValue]),
            FakeAXNode(id: "delete-button", role: "AXButton", title: "Delete Account", realActions: [.press])
        ]
    )
}

/// A "custom-canvas/incomplete AX" fixture: one opaque drawing surface with
/// no children and no actionable roles at all — the shape a
/// Metal/Core Graphics-drawn canvas typically presents to Accessibility.
/// Exercises `08-implementation-work-packages.md` WP8 verification: "A
/// custom-canvas/incomplete AX app is reported conditional/blocked rather
/// than complete."
func makeCustomCanvasAppWindow() -> FakeAXNode {
    FakeAXNode(
        id: "canvas-root-window",
        role: "AXWindow",
        title: "Custom Canvas App",
        children: [
            FakeAXNode(id: "canvas-surface", role: "AXUnknown", title: nil, realActions: [])
        ]
    )
}
