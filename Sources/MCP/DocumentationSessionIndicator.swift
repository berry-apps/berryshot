import Foundation
import SwiftUI
import BerryShotIPC

/// The persistent menu-bar indicator's data source
/// (`06-agent-documentation-security.md` section 6: "Persistent menu-bar
/// indicator while a broker session is connected... Show client name,
/// target bundle ID, mode, elapsed time, and last action"). `MCPIntegrationSettings`
/// wires `DocumentationSessionManager`'s `onChange` callback to
/// ``update(_:)`` on `enable()`; `MenuView` observes ``shared`` directly.
///
/// Kept as its own small `@MainActor` `ObservableObject` (rather than
/// folding into `MCPIntegrationSettings`) so `DocumentationSessionManager` —
/// an actor with no `@MainActor` requirement — never needs to know anything
/// about SwiftUI to publish updates; it only calls a plain
/// `@Sendable` closure.
@MainActor
public final class DocumentationSessionIndicator: ObservableObject {
    public static let shared = DocumentationSessionIndicator()

    @Published public private(set) var activeSessions: [DocumentationSessionDTO] = []
    /// Set by `MCPIntegrationSettings.enable()` to the live
    /// `DocumentationSessionManager` instance so the menu's Stop button has
    /// something to call; `nil` whenever MCP integration is off.
    public var stopHandler: (@Sendable (String) async -> Void)?

    private init() {}

    public func update(_ sessions: [DocumentationSessionDTO]) {
        activeSessions = sessions
    }

    public func clear() {
        activeSessions = []
        stopHandler = nil
    }

    public func stop(sessionID: String) {
        guard let stopHandler else { return }
        Task { await stopHandler(sessionID) }
    }
}
