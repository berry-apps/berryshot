import Foundation
import SwiftUI
import BerryShotIPC

/// Owns the GUI-side on/off lifecycle for the MCP capture broker. This is
/// the *only* code path anywhere in the app that constructs/starts a
/// `CaptureBroker`/`BrokerIPCServer` — `AppDelegate` never does, matching
/// `08-implementation-work-packages.md` WP6's requirement: "Keep
/// integration disabled by default and add explicit Privacy
/// setting/start-stop lifecycle" and the anti-pattern guard "No
/// always-running helper process."
///
/// Design note on relaunch behavior: `05-mcp-server-contract.md`/
/// `02-target-architecture.md` section 4 says the GUI "rotates [the
/// descriptor] after restart/re-enable," which only makes sense if a
/// restart is an expected resume path. So: a fresh install (or a user who
/// has never opted in) has this off, satisfying "disabled by default,"
/// but if the user previously turned it on, the next GUI launch resumes it
/// with a freshly rotated socket/token, the same way many
/// enable-a-background-capability toggles behave elsewhere in macOS
/// software. Nothing outside an explicit `true` value the user set via
/// this toggle (now or in an earlier session) ever causes a start.
@MainActor
public final class MCPIntegrationSettings: ObservableObject {
    public static let shared = MCPIntegrationSettings()

    @AppStorage("mcp_integration_enabled") private var storedEnabled: Bool = false

    /// Whether the broker/IPC server are actually listening right now —
    /// distinct from `isEnabled` so the UI can show a clear failure state
    /// (preference is "on" but startup failed) instead of silently lying.
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    private var broker: CaptureBroker?
    private var server: BrokerIPCServer?
    /// `nil` uses `BrokerIPCServer`'s real default
    /// (`~/Library/Application Support/BerryShot/MCP`). Overridable only so
    /// tests can point `enable()` at an isolated temp directory instead of
    /// the real, possibly-in-use production path; production code must
    /// always go through `.shared`, which uses the real default.
    private let baseDirectory: URL?

    public var isEnabled: Bool {
        get { storedEnabled }
        set {
            if newValue {
                enable()
            } else {
                disable()
            }
        }
    }

    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
        if storedEnabled {
            enable()
        }
    }

    /// Starts (or restarts) the broker/IPC server. Safe to call when
    /// already running (no-op beyond confirming the stored preference).
    public func enable() {
        guard !isRunning else {
            storedEnabled = true
            return
        }

        let newBroker = CaptureBroker(discovery: LiveCaptureBrokerDiscovery())
        let newServer = baseDirectory.map { BrokerIPCServer(broker: newBroker, baseDirectory: $0) } ?? BrokerIPCServer(broker: newBroker)
        do {
            _ = try newServer.start()
            broker = newBroker
            server = newServer
            isRunning = true
            storedEnabled = true
            lastErrorMessage = nil
        } catch {
            // Do not leave the toggle showing "on" for a broker that
            // failed to start — that would be exactly the kind of
            // honesty violation this plan's redaction contract elsewhere
            // insists on (D4 in 10-decisions-risks-open-questions.md: never
            // silently claim a state that is not true).
            broker = nil
            server = nil
            isRunning = false
            storedEnabled = false
            lastErrorMessage = "Could not start MCP integration: \(error)"
        }
    }

    /// Stops the broker/IPC server, closes active connections, and cancels
    /// any queued work. Safe to call when not running.
    public func disable() {
        server?.stop()
        server = nil
        broker = nil
        isRunning = false
        storedEnabled = false
        lastErrorMessage = nil
    }
}
