import CoreGraphics
import Foundation

/// WP8 guarded-interactive-automation wire types
/// (`06-agent-documentation-security.md` section 4). Every request here
/// carries a `sessionID` and is validated against that session's allowlisted
/// bundle identifier — none of these accept a bundle/path/PID of their own.

// MARK: - launch_application / activate_application

public struct LaunchApplicationRequest: Codable, Sendable, Equatable {
    public let sessionID: String
    /// Per-call approval flag required in addition to the session's
    /// `allowLaunch` (`06-agent-documentation-security.md` section 4:
    /// "requires `allowLaunch: true` in the session plus per-call user
    /// approval"). This is that second, independent gate — a session with
    /// `allowLaunch: true` still refuses to launch unless this is also
    /// `true` on this specific call.
    public let approve: Bool

    public init(sessionID: String, approve: Bool) {
        self.sessionID = sessionID
        self.approve = approve
    }
}

public struct ActivateApplicationRequest: Codable, Sendable, Equatable {
    public let sessionID: String
    public init(sessionID: String) { self.sessionID = sessionID }
}

public struct ApplicationLaunchResultDTO: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let processID: Int32
    public let wasAlreadyRunning: Bool
    public let isActive: Bool

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "bundle_id"
        case processID = "process_id"
        case wasAlreadyRunning = "was_already_running"
        case isActive = "is_active"
    }

    public init(bundleIdentifier: String, processID: Int32, wasAlreadyRunning: Bool, isActive: Bool) {
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.wasAlreadyRunning = wasAlreadyRunning
        self.isActive = isActive
    }
}

// MARK: - inspect_ui

/// The *only* five actions this whole feature can ever perform through
/// `perform_ui_action` (`06-agent-documentation-security.md` section 4:
/// "small allowlisted action enum such as `press`, `showMenu`, `increment`,
/// `decrement`, or non-sensitive `setValue`"). There is no raw AX action
/// string anywhere on the wire — a client can request one of these five
/// cases and nothing else, so an unrecognized action fails JSON Schema
/// `enum` validation before it ever reaches broker code, and the broker's
/// own `switch` over this type is exhaustive by the compiler, not by
/// convention.
public enum UIActionKind: String, Codable, Sendable, Equatable, CaseIterable {
    case press
    case showMenu
    case increment
    case decrement
    case setValue
}

public struct AXFrameDTO: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}

/// One bounded, sanitized AX node. Deliberately carries no `value` field at
/// all — not even for ordinary text fields — so there is no code path that
/// could return a secure-field value by omission-of-a-check; a caller that
/// needs a redacted screenshot of on-screen text uses
/// `documentation_session_capture_step` instead
/// (`06-agent-documentation-security.md` section 4: "Never return secure-field
/// values").
public struct AXNodeDTO: Codable, Sendable, Equatable {
    /// `nil` for a node that exists but was pruned from the tree because
    /// ``maxDepth``/``maxNodes`` was reached first — such a node is
    /// unreachable by `perform_ui_action` in this response, matching
    /// "coverage states verified/conditional/blocked/not-attempted, never
    /// claim completeness": `child_count` still reports the true number of
    /// children so a truncated subtree is visibly truncated, not silently
    /// dropped.
    public let ref: String?
    public let role: String
    public let subrole: String?
    public let title: String?
    public let descriptionText: String?
    public let enabledState: Bool
    public let focused: Bool
    public let frame: AXFrameDTO?
    /// Already intersected with the fixed ``UIActionKind`` allowlist *and*
    /// with this element's real AX-supported actions *and* with the secure/
    /// destructive guards — never the client's wish list, always what this
    /// element structurally supports and is permitted to do.
    public let actions: [UIActionKind]
    public let childCount: Int
    public let children: [AXNodeDTO]

    private enum CodingKeys: String, CodingKey {
        case ref
        case role
        case subrole
        case title
        case descriptionText = "description"
        case enabledState = "enabled"
        case focused
        case frame
        case actions
        case childCount = "child_count"
        case children
    }

    public init(
        ref: String?,
        role: String,
        subrole: String?,
        title: String?,
        descriptionText: String?,
        enabledState: Bool,
        focused: Bool,
        frame: AXFrameDTO?,
        actions: [UIActionKind],
        childCount: Int,
        children: [AXNodeDTO]
    ) {
        self.ref = ref
        self.role = role
        self.subrole = subrole
        self.title = title
        self.descriptionText = descriptionText
        self.enabledState = enabledState
        self.focused = focused
        self.frame = frame
        self.actions = actions
        self.childCount = childCount
        self.children = children
    }
}

public struct InspectUIRequest: Codable, Sendable, Equatable {
    public let sessionID: String
    /// `nil` inspects from the frontmost window's root; non-nil re-roots the
    /// snapshot at a previously returned element (still validated against
    /// the current session/PID/generation exactly like `perform_ui_action`).
    public let elementRef: String?
    public let maxDepth: Int
    public let maxNodes: Int

    public init(sessionID: String, elementRef: String? = nil, maxDepth: Int, maxNodes: Int) {
        self.sessionID = sessionID
        self.elementRef = elementRef
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
    }
}

public struct UISnapshotDTO: Codable, Sendable, Equatable {
    public let sessionID: String
    public let bundleIdentifier: String
    public let processID: Int32
    /// Bumped on every `inspect_ui` call for this session; every element ref
    /// this snapshot hands out is stamped with this generation, and
    /// `perform_ui_action`/`wait_for_ui` reject a ref stamped with any other
    /// generation (`06-agent-documentation-security.md` section 8: "Reuse
    /// stale element reference after PID/window change: rejected").
    public let generation: Int
    public let windowTitle: String
    public let root: AXNodeDTO
    public let truncatedByDepth: Bool
    public let truncatedByNodeCount: Bool

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case bundleIdentifier = "bundle_id"
        case processID = "process_id"
        case generation
        case windowTitle = "window_title"
        case root
        case truncatedByDepth = "truncated_by_depth"
        case truncatedByNodeCount = "truncated_by_node_count"
    }

    public init(
        sessionID: String,
        bundleIdentifier: String,
        processID: Int32,
        generation: Int,
        windowTitle: String,
        root: AXNodeDTO,
        truncatedByDepth: Bool,
        truncatedByNodeCount: Bool
    ) {
        self.sessionID = sessionID
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.generation = generation
        self.windowTitle = windowTitle
        self.root = root
        self.truncatedByDepth = truncatedByDepth
        self.truncatedByNodeCount = truncatedByNodeCount
    }
}

// MARK: - perform_ui_action

public struct PerformUIActionRequest: Codable, Sendable, Equatable {
    public let sessionID: String
    public let elementRef: String
    public let action: UIActionKind
    /// Only meaningful for ``UIActionKind/setValue``; bounded/sanitized
    /// before it ever reaches AX (`AXAutomationTextSanitizer`). Must be
    /// `nil` for every other action.
    public let value: String?

    public init(sessionID: String, elementRef: String, action: UIActionKind, value: String? = nil) {
        self.sessionID = sessionID
        self.elementRef = elementRef
        self.action = action
        self.value = value
    }
}

public struct UIActionResultDTO: Codable, Sendable, Equatable {
    public let sessionID: String
    public let elementRef: String
    public let action: UIActionKind
    public let performed: Bool
    public let role: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case elementRef = "element_ref"
        case action
        case performed
        case role
    }

    public init(sessionID: String, elementRef: String, action: UIActionKind, performed: Bool, role: String) {
        self.sessionID = sessionID
        self.elementRef = elementRef
        self.action = action
        self.performed = performed
        self.role = role
    }
}

// MARK: - wait_for_ui

/// Bounded predicates over allowed AX metadata only
/// (`06-agent-documentation-security.md` section 4: "Wait on bounded
/// predicates over allowed AX metadata: element appears/disappears, window
/// title changes, enabled state, focus state"). No predicate here can wait
/// on pixel content, clipboard, or any value outside this fixed list.
public enum WaitPredicateKind: String, Codable, Sendable, Equatable, CaseIterable {
    case elementAppears = "element_appears"
    case elementDisappears = "element_disappears"
    case windowTitleContains = "window_title_contains"
    case enabledStateEquals = "enabled_state_equals"
    case focusedStateEquals = "focused_state_equals"
}

public struct WaitForUIRequest: Codable, Sendable, Equatable {
    public let sessionID: String
    public let predicate: WaitPredicateKind
    /// Used by `elementAppears`/`elementDisappears`: matched against role
    /// (exact) and/or title (substring), at least one of which must be set.
    public let roleQuery: String?
    public let titleQuery: String?
    /// Used by `enabledStateEquals`/`focusedStateEquals`.
    public let elementRef: String?
    public let expectedBool: Bool?
    public let timeoutMilliseconds: Int

    public init(
        sessionID: String,
        predicate: WaitPredicateKind,
        roleQuery: String? = nil,
        titleQuery: String? = nil,
        elementRef: String? = nil,
        expectedBool: Bool? = nil,
        timeoutMilliseconds: Int
    ) {
        self.sessionID = sessionID
        self.predicate = predicate
        self.roleQuery = roleQuery
        self.titleQuery = titleQuery
        self.elementRef = elementRef
        self.expectedBool = expectedBool
        self.timeoutMilliseconds = timeoutMilliseconds
    }
}

public struct UIWaitResultDTO: Codable, Sendable, Equatable {
    public let sessionID: String
    public let satisfied: Bool
    public let timedOut: Bool
    public let elapsedMilliseconds: Int

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case satisfied
        case timedOut = "timed_out"
        case elapsedMilliseconds = "elapsed_ms"
    }

    public init(sessionID: String, satisfied: Bool, timedOut: Bool, elapsedMilliseconds: Int) {
        self.sessionID = sessionID
        self.satisfied = satisfied
        self.timedOut = timedOut
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}
