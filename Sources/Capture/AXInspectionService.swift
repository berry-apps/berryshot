import Foundation
import AppKit
@preconcurrency import ApplicationServices
import BerryShotIPC

/// One AX node as observed by ``AXInspecting/snapshot(pid:root:maxDepth:maxNodes:)``,
/// before `UIElementRegistry` assigns opaque `ref` strings and produces the
/// wire-level `AXNodeDTO` (`06-agent-documentation-security.md` section 4:
/// "bounded safe AX snapshot serializer with opaque short-lived element
/// refs"). `handle` is an implementation-private token
/// (`LiveAXElementHandle` wrapping a real `AXUIElement` in production, a
/// synthetic identifier in tests) that never itself crosses the wire — only
/// `UIElementRegistry`-issued opaque strings do.
public struct AXObservedNode: Sendable {
    public let handle: any Sendable
    public let role: String
    public let subrole: String?
    public let title: String?
    public let descriptionText: String?
    public let enabledState: Bool
    public let focused: Bool
    public let frame: CGRect?
    /// Already intersected with the fixed ``UIActionKind`` allowlist, this
    /// element's real supported actions, and the secure/destructive guards —
    /// see ``LiveAXInspecting``'s doc comment for exactly how.
    public let supportedActions: [UIActionKind]
    /// The element's *true* child count, even when ``children`` was
    /// truncated by `maxDepth`/`maxNodes` — so a truncated subtree is
    /// visibly truncated in the DTO rather than silently reported as
    /// childless.
    public let childCount: Int
    public let children: [AXObservedNode]

    public init(
        handle: any Sendable,
        role: String,
        subrole: String?,
        title: String?,
        descriptionText: String?,
        enabledState: Bool,
        focused: Bool,
        frame: CGRect?,
        supportedActions: [UIActionKind],
        childCount: Int,
        children: [AXObservedNode]
    ) {
        self.handle = handle
        self.role = role
        self.subrole = subrole
        self.title = title
        self.descriptionText = descriptionText
        self.enabledState = enabledState
        self.focused = focused
        self.frame = frame
        self.supportedActions = supportedActions
        self.childCount = childCount
        self.children = children
    }
}

public struct AXInspectionSnapshot: Sendable {
    public let windowTitle: String
    public let root: AXObservedNode
    public let truncatedByDepth: Bool
    public let truncatedByNodeCount: Bool

    public init(windowTitle: String, root: AXObservedNode, truncatedByDepth: Bool, truncatedByNodeCount: Bool) {
        self.windowTitle = windowTitle
        self.root = root
        self.truncatedByDepth = truncatedByDepth
        self.truncatedByNodeCount = truncatedByNodeCount
    }
}

public enum AXInspectionError: Error, Sendable, Equatable {
    case applicationNotAvailable
    case noFocusedWindow
    case elementNotAvailable
    case actionBlocked
    case actionFailed
}

/// Everything `CaptureBroker` needs to read/act on an AX tree, narrowed to
/// exactly the operations WP8 uses. Kept as a protocol (mirroring
/// `CaptureBrokerDiscovering`/`CaptureBrokerWindowCapturing` from WP6/WP7) so
/// broker-level security-matrix tests (wrong bundle, stale ref, secure
/// field, blocked action) can run against a deterministic fake tree instead
/// of requiring a real Accessibility-permitted GUI session — real AXUIElement
/// behavior itself is exercised only by manual/real-device testing, exactly
/// like WP2/WP3's ScreenCaptureKit paths.
public protocol AXInspecting: Sendable {
    func snapshot(pid: pid_t, root: (any Sendable)?, maxDepth: Int, maxNodes: Int) throws -> AXInspectionSnapshot
    /// Performs `action` on `handle`. Implementations must re-validate the
    /// secure/destructive guards against the *live* element immediately
    /// before acting, not only trust the caller's snapshot-time
    /// classification (defense in depth against a dynamic UI that changed
    /// role/title between `inspect_ui` and `perform_ui_action`).
    func performAction(pid: pid_t, handle: any Sendable, action: UIActionKind, value: String?) throws -> Bool
    /// Re-resolves `handle`'s live enabled/focused state for
    /// `wait_for_ui`'s `enabledStateEquals`/`focusedStateEquals` predicates.
    /// Returns `nil` if the element can no longer be resolved.
    func currentState(pid: pid_t, handle: any Sendable) -> (enabled: Bool, focused: Bool)?
}

/// Opaque handle wrapping a real `AXUIElement`. `@unchecked Sendable`: an
/// `AXUIElement` is a `CFTypeRef`; this process already treats
/// `ApplicationServices` AX types as usable across the same boundaries
/// `AccessibilityBridge`/`CaptureBroker` do (`@preconcurrency import
/// ApplicationServices`), and every access here goes through this one
/// immutable wrapper rather than passing raw `AXUIElement` across an actor
/// boundary implicitly.
public struct LiveAXElementHandle: @unchecked Sendable {
    public let element: AXUIElement
    public init(_ element: AXUIElement) { self.element = element }
}

/// Case-insensitive substring match against a fixed vocabulary drawn
/// directly from `06-agent-documentation-security.md` section 5's risk
/// table ("External side effect: send, publish, upload, purchase, install";
/// "Destructive: delete, reset, revoke, uninstall") and section 8's
/// verification example ("Attempt blocked role/action such as
/// Delete/Buy/Send: rejected"). This is an explicit *defense-in-depth*
/// layer on top of the structural allowlist/secure-role guards — AX exposes
/// no structural "this control is destructive" marker, so text matching on
/// the element's own title/description is the only signal available for
/// this specific case. A control whose title never mentions one of these
/// words is not covered by this guard; see the WP8 PR's "Known gaps"
/// section.
public enum DestructiveActionGuard {
    static let blockedKeywords: [String] = [
        "delete", "remove", "erase", "uninstall", "reset", "revoke",
        "purchase", "buy", "pay", "subscribe",
        "send", "publish", "upload", "install", "download"
    ]

    public static func isBlocked(title: String?, description: String?) -> Bool {
        let haystack = [title, description].compactMap { $0 }.joined(separator: " ").lowercased()
        guard !haystack.isEmpty else { return false }
        return blockedKeywords.contains { haystack.contains($0) }
    }
}

/// Structural (role/subrole-based) secure-field guard —
/// `06-agent-documentation-security.md` section 4: "Never return
/// secure-field values"; section 9: "No automatic login, CAPTCHA,
/// credentials". Checked independently at snapshot time (so a secure field
/// never advertises any action) and again immediately before performing an
/// action (defense in depth).
public enum SecureElementGuard {
    static let secureRolesAndSubroles: Set<String> = ["AXSecureTextField"]

    public static func isSecure(role: String, subrole: String?) -> Bool {
        if secureRolesAndSubroles.contains(role) { return true }
        if let subrole, secureRolesAndSubroles.contains(subrole) { return true }
        return false
    }
}

/// Bounds/sanitizes a `setValue` payload before it ever reaches AX. Kept
/// local to this file (rather than reusing `Sources/MCP/CaptureBrokerCaptureOperations.swift`'s
/// `BrokerTextSanitizer`) so `Sources/Capture` does not take a dependency on
/// `Sources/MCP` — the existing dependency direction in this codebase runs
/// the other way (`CaptureBroker` already imports `WindowCaptureService`).
public enum AXAutomationTextSanitizer {
    public static let maxLength = 500

    public static func sanitize(_ text: String) -> String {
        let allowedScalars = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(allowedScalars))
        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength))
    }
}

/// Roles `setValue` is offered for. Deliberately narrow — ordinary editable
/// text controls only, never secure fields (excluded separately by
/// ``SecureElementGuard``) and never controls whose semantics are a
/// selection/toggle rather than free text.
private let setValueEligibleRoles: Set<String> = [
    "AXTextField", "AXTextArea", "AXComboBox"
]

/// Maps a fixed, closed set of real AX action-name constants to
/// ``UIActionKind``. Any AX action name outside this map (there are dozens
/// in the wild, including app-defined custom actions) is silently dropped —
/// never surfaced, never invocable — which is what makes the action
/// allowlist a *by-construction* guarantee rather than best-effort
/// filtering: `LiveAXInspecting.performAction` can only ever call
/// `AXUIElementPerformAction` with one of these four fixed string constants
/// or set `kAXValueAttribute` for `setValue`, never a client- or
/// AX-supplied action name.
private func mapSupportedAXActions(_ axActionNames: [String]) -> [UIActionKind] {
    var mapped: [UIActionKind] = []
    if axActionNames.contains(kAXPressAction) { mapped.append(.press) }
    if axActionNames.contains(kAXShowMenuAction) { mapped.append(.showMenu) }
    if axActionNames.contains(kAXIncrementAction) { mapped.append(.increment) }
    if axActionNames.contains(kAXDecrementAction) { mapped.append(.decrement) }
    return mapped
}

/// Production `AXInspecting` adapter over real `AXUIElement` calls, using
/// the same low-level attribute-copy patterns as `AccessibilityBridge`
/// (`Sources/Capture/AccessibilityBridge.swift`). Never reads
/// `kAXValueAttribute` for *display* purposes (no node ever carries a
/// `value` field — see `AXNodeDTO`'s doc comment); `kAXValueAttribute` is
/// only ever written to (via `setValue`), never read back and returned.
public struct LiveAXInspecting: AXInspecting {
    /// Text attributes are sanitized/bounded the same way
    /// `BrokerTextSanitizer` bounds application/window names
    /// (`06-agent-documentation-security.md` section 7: "Manifest
    /// titles/AX strings are sanitized and length-bounded").
    static let maxTextLength = 300

    public init() {}

    public func snapshot(pid: pid_t, root: (any Sendable)?, maxDepth: Int, maxNodes: Int) throws -> AXInspectionSnapshot {
        let appElement = AXUIElementCreateApplication(pid)
        let rootElement: AXUIElement
        if let root {
            guard let liveHandle = root as? LiveAXElementHandle else { throw AXInspectionError.elementNotAvailable }
            rootElement = liveHandle.element
        } else {
            guard let focusedWindow = Self.copyElement(appElement, attribute: kAXFocusedWindowAttribute) else {
                throw AXInspectionError.noFocusedWindow
            }
            rootElement = focusedWindow
        }

        let windowTitle: String
        if let focusedWindow = Self.copyElement(appElement, attribute: kAXFocusedWindowAttribute) {
            windowTitle = Self.copyString(focusedWindow, attribute: kAXTitleAttribute).map(Self.sanitizedString) ?? ""
        } else {
            windowTitle = ""
        }

        var nodeCount = 0
        var truncatedByNodeCount = false
        var truncatedByDepth = false
        let node = Self.walk(
            rootElement,
            depth: 0,
            maxDepth: maxDepth,
            maxNodes: maxNodes,
            nodeCount: &nodeCount,
            truncatedByNodeCount: &truncatedByNodeCount,
            truncatedByDepth: &truncatedByDepth
        )
        return AXInspectionSnapshot(windowTitle: windowTitle, root: node, truncatedByDepth: truncatedByDepth, truncatedByNodeCount: truncatedByNodeCount)
    }

    public func performAction(pid: pid_t, handle: any Sendable, action: UIActionKind, value: String?) throws -> Bool {
        guard let liveHandle = handle as? LiveAXElementHandle else { throw AXInspectionError.elementNotAvailable }
        let element = liveHandle.element

        // Defense in depth: re-check the *live* element's role/subrole/title
        // right before acting, independent of whatever the broker's cached
        // snapshot metadata said (see this type's doc comment).
        let role = Self.copyString(element, attribute: kAXRoleAttribute).map(Self.sanitizedString) ?? ""
        let subrole = Self.copyString(element, attribute: kAXSubroleAttribute).map(Self.sanitizedString)
        let title = Self.copyString(element, attribute: kAXTitleAttribute).map(Self.sanitizedString)
        let description = Self.copyString(element, attribute: kAXDescriptionAttribute).map(Self.sanitizedString)

        guard !SecureElementGuard.isSecure(role: role, subrole: subrole) else { throw AXInspectionError.actionBlocked }
        guard !DestructiveActionGuard.isBlocked(title: title, description: description) else { throw AXInspectionError.actionBlocked }

        switch action {
        case .press:
            return Self.perform(element, kAXPressAction)
        case .showMenu:
            return Self.perform(element, kAXShowMenuAction)
        case .increment:
            return Self.perform(element, kAXIncrementAction)
        case .decrement:
            return Self.perform(element, kAXDecrementAction)
        case .setValue:
            guard setValueEligibleRoles.contains(role) else { throw AXInspectionError.actionBlocked }
            let sanitized = AXAutomationTextSanitizer.sanitize(value ?? "")
            let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, sanitized as CFTypeRef)
            return result == .success
        }
    }

    public func currentState(pid: pid_t, handle: any Sendable) -> (enabled: Bool, focused: Bool)? {
        guard let liveHandle = handle as? LiveAXElementHandle else { return nil }
        let element = liveHandle.element
        let enabled = Self.copyBool(element, attribute: kAXEnabledAttribute) ?? false
        let focused = Self.copyBool(element, attribute: kAXFocusedAttribute) ?? false
        return (enabled, focused)
    }

    // MARK: - Tree walk

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        maxNodes: Int,
        nodeCount: inout Int,
        truncatedByNodeCount: inout Bool,
        truncatedByDepth: inout Bool
    ) -> AXObservedNode {
        nodeCount += 1

        let role = copyString(element, attribute: kAXRoleAttribute).map(sanitizedString) ?? ""
        let subrole = copyString(element, attribute: kAXSubroleAttribute).map(sanitizedString)
        let title = copyString(element, attribute: kAXTitleAttribute).map(sanitizedString)
        let description = copyString(element, attribute: kAXDescriptionAttribute).map(sanitizedString)
        let enabledState = copyBool(element, attribute: kAXEnabledAttribute) ?? true
        let focused = copyBool(element, attribute: kAXFocusedAttribute) ?? false
        let frame = copyFrame(element)

        let isSecure = SecureElementGuard.isSecure(role: role, subrole: subrole)
        let isBlockedByKeyword = DestructiveActionGuard.isBlocked(title: title, description: description)

        var actions: [UIActionKind] = []
        if !isSecure && !isBlockedByKeyword {
            var actionNamesRef: CFArray?
            if AXUIElementCopyActionNames(element, &actionNamesRef) == .success, let names = actionNamesRef as? [String] {
                actions = mapSupportedAXActions(names)
            }
            if setValueEligibleRoles.contains(role) {
                var settable: DarwinBoolean = false
                if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue {
                    actions.append(.setValue)
                }
            }
        }

        let allChildren = copyChildren(element)
        let childCount = allChildren.count

        var children: [AXObservedNode] = []
        if depth + 1 > maxDepth {
            if childCount > 0 { truncatedByDepth = true }
        } else {
            for child in allChildren {
                if nodeCount >= maxNodes {
                    truncatedByNodeCount = true
                    break
                }
                children.append(walk(
                    child,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    maxNodes: maxNodes,
                    nodeCount: &nodeCount,
                    truncatedByNodeCount: &truncatedByNodeCount,
                    truncatedByDepth: &truncatedByDepth
                ))
            }
        }

        return AXObservedNode(
            handle: LiveAXElementHandle(element),
            role: role,
            subrole: subrole,
            title: title,
            descriptionText: description,
            enabledState: enabledState,
            focused: focused,
            frame: frame,
            supportedActions: actions,
            childCount: childCount,
            children: children
        )
    }

    // MARK: - Low-level AX helpers

    private static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    private static func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success, let ref else { return nil }
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (ref as! AXUIElement)
    }

    private static func copyChildren(_ element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return [] }
        return children
    }

    private static func copyString(_ element: AXUIElement, attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func copyBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success, let value = ref else { return nil }
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }

    private static func copyFrame(_ element: AXUIElement) -> CGRect? {
        var originRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &originRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }
        guard let ov = originRef, CFGetTypeID(ov) == AXValueGetTypeID(),
              let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(ov as! AXValue, .cgPoint, &origin)
        // swiftlint:disable:next force_cast
        AXValueGetValue(sv as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private static func sanitizedString(_ text: String) -> String {
        let allowedScalars = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(allowedScalars))
        guard cleaned.count > maxTextLength else { return cleaned }
        return String(cleaned.prefix(maxTextLength))
    }
}
