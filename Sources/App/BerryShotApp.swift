import SwiftUI
import Speech
import AVFoundation

struct MenuView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var captureCoordinator = CaptureCoordinator.shared
    
    @AppStorage("captureShortcut") private var shortcutData: Data = Data()
    
    private var currentShortcut: Shortcut {
        if let decoded = try? JSONDecoder().decode(Shortcut.self, from: shortcutData) {
            return decoded
        }
        return Shortcut.defaultShortcut
    }
    
    var body: some View {
        let shortcut = currentShortcut
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
            if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
               let rawImage = NSImage(contentsOf: url) {
                Image(nsImage: {
                    rawImage.isTemplate = true
                    rawImage.size = NSSize(width: 18, height: 18)
                    return rawImage
                }())
            } else {
                Image(systemName: "camera.viewfinder")
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce single instance
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.tan.berryshot")
        if runningApps.count > 1 {
            print("Another instance is already running. Terminating.")
            NSApplication.shared.terminate(nil)
            return
        }
        
        // App setup
        _ = CaptureCoordinator.shared
        
        // Load AppIcon from module resources robustly
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
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
    }
}
