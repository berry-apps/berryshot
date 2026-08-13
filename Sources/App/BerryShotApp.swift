import SwiftUI
import Speech
import AVFoundation
#if canImport(Darwin)
import Darwin
#endif

private var resourceBundle: Bundle? {
    let candidates = [
        Bundle.main.bundlePath + "/Contents/Resources/BerryShot_BerryShot.bundle",
        Bundle.main.bundlePath + "/Contents/Resources/BerryShot_BerryShot_BerryShot.bundle"
    ]
    for path in candidates {
        if let bundle = Bundle(path: path) { return bundle }
    }
    return nil
}

struct MenuView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var captureCoordinator = CaptureCoordinator.shared
    /// WP8 persistent indicator (`06-agent-documentation-security.md`
    /// section 6: "Persistent menu-bar indicator while a broker session is
    /// connected... Show client name, target bundle ID, mode, elapsed time,
    /// and last action"). Empty whenever no MCP documentation session is
    /// active, which is the common case, so this section of the menu is
    /// invisible unless an agent is actually connected.
    @ObservedObject var documentationIndicator = DocumentationSessionIndicator.shared

    @AppStorage("captureShortcut") private var shortcutData: Data = Data()
    @AppStorage("scrollCaptureShortcut") private var scrollShortcutData: Data = Data()
    @AppStorage("appWindowCaptureShortcut") private var appWindowShortcutData: Data = Data()
    @AppStorage("appWindowRecordingShortcut") private var appWindowRecordingShortcutData: Data = Data()

    private var currentShortcut: Shortcut {
        if let decoded = try? JSONDecoder().decode(Shortcut.self, from: shortcutData) {
            return decoded
        }
        return Shortcut.defaultShortcut
    }

    private var currentScrollShortcut: Shortcut {
        if let decoded = try? JSONDecoder().decode(Shortcut.self, from: scrollShortcutData) {
            return decoded
        }
        return Shortcut.defaultScrollShortcut
    }

    private var currentAppWindowShortcut: Shortcut {
        if let decoded = try? JSONDecoder().decode(Shortcut.self, from: appWindowShortcutData) {
            return decoded
        }
        return Shortcut.defaultAppWindowCaptureShortcut
    }

    private var currentAppWindowRecordingShortcut: Shortcut {
        if let decoded = try? JSONDecoder().decode(Shortcut.self, from: appWindowRecordingShortcutData) {
            return decoded
        }
        return Shortcut.defaultAppWindowRecordingShortcut
    }

    var body: some View {
        let shortcut = currentShortcut
        let scrollShortcut = currentScrollShortcut
        let appWindowShortcut = currentAppWindowShortcut
        let appWindowRecordingShortcut = currentAppWindowRecordingShortcut
        let captureButton = Button("Capture Region") {
            Task {
                await captureCoordinator.startCapture()
            }
        }

        if let key = shortcut.swiftuiKeyEquivalent {
            captureButton.keyboardShortcut(key, modifiers: shortcut.swiftuiModifiers)
        } else {
            captureButton
        }

        let appWindowButton = Button("Capture App or Window…") {
            captureCoordinator.startApplicationWindowCapture()
        }
        if let appWindowKey = appWindowShortcut.swiftuiKeyEquivalent {
            appWindowButton.keyboardShortcut(appWindowKey, modifiers: appWindowShortcut.swiftuiModifiers)
        } else {
            appWindowButton
        }

        let scrollButton = Button("Scroll Capture…") {
            captureCoordinator.startScrollCapture()
        }
        if let scrollKey = scrollShortcut.swiftuiKeyEquivalent {
            scrollButton.keyboardShortcut(scrollKey, modifiers: scrollShortcut.swiftuiModifiers)
        } else {
            scrollButton
        }

        let appWindowRecordingButton = Button("Record App or Window…") {
            captureCoordinator.startApplicationWindowRecording()
        }
        if let appWindowRecordingKey = appWindowRecordingShortcut.swiftuiKeyEquivalent {
            appWindowRecordingButton.keyboardShortcut(appWindowRecordingKey, modifiers: appWindowRecordingShortcut.swiftuiModifiers)
        } else {
            appWindowRecordingButton
        }
        
        if !documentationIndicator.activeSessions.isEmpty {
            Divider()
            ForEach(documentationIndicator.activeSessions, id: \.sessionID) { session in
                Menu("Agent session: \(session.displayName)") {
                    Text("Application: \(session.bundleIdentifier)")
                    Text("Mode: \(session.mode == .interactive ? "Interactive" : "Read-only")")
                    Text("Status: \(session.status.rawValue.capitalized)")
                    Text("Last action: \(session.lastActionDescription)")
                    Text("Artifacts: \(session.artifactCount)/\(session.maxArtifacts)")
                    Divider()
                    Button("Stop Session") {
                        documentationIndicator.stop(sessionID: session.sessionID)
                    }
                }
            }
        }

        Divider()

        Button("Check for Updates...") {
            Task {
                await UpdateManager.shared.checkForUpdates(showUI: true)
            }
        }
        
        Divider()
        
        Button("Settings...") {
            NSApp.activate(ignoringOtherApps: true)
            if #available(macOS 13.0, *) {
                openSettings()
            } else {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .keyboardShortcut(",", modifiers: .command)
        
        Divider()
        
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

@main
struct BerryShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            MenuView()
        } label: {
            MenuBarIconView()
        }
        
        Settings {
            SettingsView()
        }
    }
}

struct MenuBarIconView: View {
    var body: some View {
        if let icon = loadMenuBarIcon() {
            Image(nsImage: icon)
        } else {
            Image(systemName: "camera.viewfinder")
        }
    }
    
    private func loadMenuBarIcon() -> NSImage? {
        // Try multiple paths for the icon
        let paths = [
            // App bundle Resources
            Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
            // Swift Package resource bundle (safe access)
            resourceBundle?.path(forResource: "MenuBarIcon", ofType: "png"),
            // Relative to executable
            Bundle.main.bundlePath + "/Contents/Resources/MenuBarIcon.png",
            Bundle.main.bundlePath + "/Contents/Resources/BerryShot_BerryShot.bundle/MenuBarIcon.png"
        ]
        
        for path in paths.compactMap({ $0 }) {
            if let image = NSImage(contentsOfFile: path) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                return image
            }
        }
        return nil
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `BrokerIPCServer.acceptConnection` already sets `SO_NOSIGPIPE` on
        // every accepted IPC socket, but that is a per-fd opt-in that only
        // covers writes this app remembers to protect. `SIGPIPE`'s default
        // disposition terminates the whole process on ANY broken-pipe
        // write anywhere (a future log/upload/socket path that forgets the
        // flag), which is never the right behavior for a long-lived GUI
        // app — the same reasoning `MCPServer/main.swift` already applies
        // to the MCP helper. Ignore it process-wide so such writes fail
        // with `EPIPE` instead.
        signal(SIGPIPE, SIG_IGN)

        // Enforce single instance
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.tan.berryshot")
        if runningApps.count > 1 {
            print("Another instance is already running. Terminating.")
            NSApplication.shared.terminate(nil)
            return
        }
        
        // App setup
        _ = CaptureCoordinator.shared

        // Instantiates the MCP integration settings singleton. This does
        // NOT unconditionally start the capture broker/IPC server — see
        // MCPIntegrationSettings' init(), which only resumes it if the
        // user previously turned the Privacy setting on. A fresh install
        // (or anyone who has never enabled it) starts nothing here.
        _ = MCPIntegrationSettings.shared
        
        // Load AppIcon from module resources robustly
        if let bundle = resourceBundle,
           let url = bundle.url(forResource: "AppIcon", withExtension: "png"),
           let iconImage = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = iconImage
            print("[BerryShot] Successfully loaded AppIcon.png")
        } else {
            print("[BerryShot] Failed to load AppIcon.png")
        }
        
        // Request permissions sequentially to prevent macOS tccd from glitching and showing multiple overlapping windows
        Task {
            if #available(macOS 14.4, *) {
                if !CGPreflightScreenCaptureAccess() {
                    await MainActor.run {
                        NSApp.activate(ignoringOtherApps: true)
                        _ = CGRequestScreenCaptureAccess()
                    }
                }
            }
        }

        // Ensure the app starts as an accessory (menu bar only, no dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Open Settings window on first launch so the user knows the app is running
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        
        setupEditMenu()
        print("[BerryShot] App launched successfully. Look for BerryShot in the menu bar (top right).")
    }
    
    @MainActor
    private func setupEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        
        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        editMenu.addItem(undoItem)
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(cutItem)
        editMenu.addItem(copyItem)
        editMenu.addItem(pasteItem)
        editMenu.addItem(selectAllItem)
        
        editMenuItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in menu bar even if all windows are closed
    }
}
