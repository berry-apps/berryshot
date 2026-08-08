import AppKit
import Foundation

/// Everything `CaptureBroker` needs for `launch_application`/
/// `activate_application`, narrowed to exactly what
/// `06-agent-documentation-security.md` section 4 permits: "Use
/// `NSRunningApplication.activate` or `NSWorkspace` APIs... No arbitrary
/// application path. No install, update, login item, URL scheme, file-open
/// payload, or command-line arguments." There is no method on this protocol
/// that accepts a path, URL scheme, or argument array — only a bundle
/// identifier — so those anti-pattern guards hold by construction, not by
/// convention.
public protocol ApplicationLaunching: Sendable {
    /// The PID of a currently running instance of `bundleIdentifier`, if
    /// any. Used to decide launch-vs-already-running and to resolve the PID
    /// every AX operation needs.
    func runningProcessID(bundleIdentifier: String) -> Int32?
    /// Launches `bundleIdentifier` via `NSWorkspace.openApplication` with no
    /// path, URL, or configuration beyond the identifier itself, and returns
    /// its PID once launched.
    func launch(bundleIdentifier: String) async throws -> Int32
    /// Activates (brings to front) an already-running instance. Returns
    /// `false` if no running instance exists — this method never launches.
    func activate(bundleIdentifier: String) -> Bool
}

public enum ApplicationLaunchingError: Error, Sendable {
    case applicationNotFound
    case launchFailed
}

/// Production `ApplicationLaunching` adapter. Every method resolves the
/// target exclusively by bundle identifier through `NSWorkspace`/
/// `NSRunningApplication` — never a filesystem path a caller supplied.
public struct LiveApplicationLaunching: ApplicationLaunching {
    public init() {}

    public func runningProcessID(bundleIdentifier: String) -> Int32? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.processIdentifier
    }

    public func launch(bundleIdentifier: String) async throws -> Int32 {
        if let existing = runningProcessID(bundleIdentifier: bundleIdentifier) {
            return existing
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw ApplicationLaunchingError.applicationNotFound
        }
        // `NSWorkspace.openApplication` is the modern, non-deprecated
        // replacement for `launchApplication(withBundleIdentifier:)`; it
        // takes only a resolved application `URL` and a bare, empty
        // `OpenConfiguration` — no arguments, no URL-scheme payload, no
        // document to open (`06-agent-documentation-security.md` section 4:
        // "No... URL scheme, file-open payload, or command-line
        // arguments").
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return app.processIdentifier
        } catch {
            throw ApplicationLaunchingError.launchFailed
        }
    }

    public func activate(bundleIdentifier: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return false
        }
        // `.activateIgnoringOtherApps` is deprecated/no-op on macOS 14+; a
        // bare `activate()` is the current API for bringing another app's
        // windows to the front (still no path/URL/argument involved).
        return app.activate()
    }
}
