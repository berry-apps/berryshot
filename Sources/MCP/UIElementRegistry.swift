import Foundation
import BerryShotIPC

/// Assigns opaque, short-lived element references for `inspect_ui` snapshots
/// and resolves them back for `perform_ui_action`/`wait_for_ui`
/// (`06-agent-documentation-security.md` section 4: "Generate short-lived
/// opaque element references bound to session, PID, and AX snapshot
/// generation"; anti-pattern guard: "No durable raw AX object references").
///
/// Three independent things must all still match for a ref to resolve:
/// session ID, PID, and generation. `generation` is bumped by
/// ``beginGeneration(sessionID:)`` on every `inspect_ui` call for a session,
/// which also purges every ref that call's session previously issued — so a
/// ref from a superseded snapshot (the window changed, the app relaunched
/// with a new PID, or the caller simply inspected again) is rejected even if
/// its TTL has not elapsed yet. This is the mechanism behind
/// `06-agent-documentation-security.md` section 8: "Reuse stale element
/// reference after PID/window change: rejected."
public actor UIElementRegistry {
    public struct Entry: Sendable {
        public let handle: any Sendable
        public let sessionID: String
        public let pid: pid_t
        public let generation: Int
        public let role: String
        public let subrole: String?
        public let title: String?
        public let descriptionText: String?
        /// Exactly the actions `inspect_ui` advertised for this node —
        /// already filtered by the secure/destructive guards and real
        /// AX support (`AXObservedNode.supportedActions`). `perform_ui_action`
        /// re-checks membership here (not just the client-supplied action
        /// argument) so a forged/relabeled request can never perform an
        /// action this node was never offered for.
        public let advertisedActions: [UIActionKind]
        public let createdAt: Date
    }

    public enum ResolutionFailure: Error, Sendable, Equatable {
        case notFound
        case expired
        case sessionMismatch
        case pidMismatch
        case generationMismatch
    }

    /// A ref is only ever meant to be used within the same `inspect_ui` ->
    /// `perform_ui_action`/`wait_for_ui` round trip an agent is actively
    /// driving, not stored for later — bounding its lifetime independently
    /// of the session TTL keeps a long documentation session from
    /// accumulating unbounded live-AXUIElement-shaped memory.
    public static let defaultRefTTL: TimeInterval = 180

    private let refTTL: TimeInterval
    private var entries: [String: Entry] = [:]
    private var refsBySession: [String: Set<String>] = [:]
    private var generationBySession: [String: Int] = [:]

    public init(refTTL: TimeInterval = UIElementRegistry.defaultRefTTL) {
        self.refTTL = refTTL
    }

    /// Starts a fresh generation for `sessionID` and discards every ref that
    /// session previously issued. Must be called once per `inspect_ui` call
    /// before registering the new snapshot's nodes.
    @discardableResult
    public func beginGeneration(sessionID: String) -> Int {
        let next = (generationBySession[sessionID] ?? 0) + 1
        generationBySession[sessionID] = next
        if let staleRefs = refsBySession[sessionID] {
            for ref in staleRefs { entries.removeValue(forKey: ref) }
        }
        refsBySession[sessionID] = []
        return next
    }

    public func currentGeneration(sessionID: String) -> Int {
        generationBySession[sessionID] ?? 0
    }

    /// Registers one node (already assumed to belong to `generation`) and
    /// returns its opaque ref.
    public func register(
        handle: any Sendable,
        sessionID: String,
        pid: pid_t,
        generation: Int,
        role: String,
        subrole: String?,
        title: String?,
        descriptionText: String?,
        advertisedActions: [UIActionKind]
    ) -> String {
        purgeExpired()
        let ref = UUID().uuidString
        entries[ref] = Entry(
            handle: handle, sessionID: sessionID, pid: pid, generation: generation,
            role: role, subrole: subrole, title: title, descriptionText: descriptionText,
            advertisedActions: advertisedActions, createdAt: Date()
        )
        refsBySession[sessionID, default: []].insert(ref)
        return ref
    }

    /// Recursively registers every node in `tree` under `sessionID`/`pid`/
    /// `generation` and returns the wire-level `AXNodeDTO` with opaque refs
    /// assigned in the same shape. Callers must call
    /// ``beginGeneration(sessionID:)`` first so `generation` is fresh.
    public func registerTree(_ tree: AXObservedNode, sessionID: String, pid: pid_t, generation: Int) -> AXNodeDTO {
        let ref = register(
            handle: tree.handle, sessionID: sessionID, pid: pid, generation: generation,
            role: tree.role, subrole: tree.subrole, title: tree.title, descriptionText: tree.descriptionText,
            advertisedActions: tree.supportedActions
        )
        let children = tree.children.map { registerTree($0, sessionID: sessionID, pid: pid, generation: generation) }
        return AXNodeDTO(
            ref: ref,
            role: tree.role,
            subrole: tree.subrole,
            title: tree.title,
            descriptionText: tree.descriptionText,
            enabledState: tree.enabledState,
            focused: tree.focused,
            frame: tree.frame.map(AXFrameDTO.init),
            actions: tree.supportedActions,
            childCount: tree.childCount,
            children: children
        )
    }

    /// Resolves `ref`, requiring it to match `sessionID`, `pid`, and the
    /// session's *current* generation exactly.
    public func resolve(ref: String, sessionID: String, pid: pid_t) -> Result<Entry, ResolutionFailure> {
        purgeExpired()
        guard let entry = entries[ref] else { return .failure(.notFound) }
        guard Date().timeIntervalSince(entry.createdAt) <= refTTL else {
            remove(ref)
            return .failure(.expired)
        }
        guard entry.sessionID == sessionID else { return .failure(.sessionMismatch) }
        guard entry.pid == pid else { return .failure(.pidMismatch) }
        guard entry.generation == currentGeneration(sessionID: sessionID) else { return .failure(.generationMismatch) }
        return .success(entry)
    }

    /// Drops every ref belonging to `sessionID`. Called when a documentation
    /// session ends/expires/is stopped.
    public func clearSession(_ sessionID: String) {
        if let refs = refsBySession.removeValue(forKey: sessionID) {
            for ref in refs { entries.removeValue(forKey: ref) }
        }
        generationBySession.removeValue(forKey: sessionID)
    }

    private func remove(_ ref: String) {
        guard let entry = entries.removeValue(forKey: ref) else { return }
        refsBySession[entry.sessionID]?.remove(ref)
    }

    private func purgeExpired() {
        let now = Date()
        let expired = entries.filter { now.timeIntervalSince($0.value.createdAt) > refTTL }.map(\.key)
        for ref in expired { remove(ref) }
    }

    // MARK: - Test-only introspection

    var entryCount: Int { entries.count }
}
