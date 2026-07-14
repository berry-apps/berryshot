import Foundation
import AppKit
@preconcurrency import ApplicationServices

/// Manages Accessibility permission for scroll capture.
@MainActor
public class AccessibilityManager {
    public static let shared = AccessibilityManager()

    private init() {}

    /// Returns true if the app currently has Accessibility access.
    public var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    private var hasRequestedSystemPrompt = false

    /// Prompt the user for Accessibility permission if not already granted.
    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        if isAccessibilityGranted { return true }
        
        let defaults = UserDefaults.standard
        let requestedKey = "hasRequestedAccessibilitySystemPrompt"
        hasRequestedSystemPrompt = defaults.bool(forKey: requestedKey)
        
        if !hasRequestedSystemPrompt {
            // First time: rely on the system's built-in prompt
            defaults.set(true, forKey: requestedKey)
            hasRequestedSystemPrompt = true
            return Self.promptForAccessibility()
        } else {
            // Subsequent times: system prompt might be suppressed, show our custom alert
            // We still call the AX check without prompt just to be sure, though it returns false
            showPermissionAlert()
            return false
        }
    }

    // nonisolated so we can access global C constants safely
    private static nonisolated func promptForAccessibility() -> Bool {
        // Using unsafe to bridge the C global constant in Swift 6 strict concurrency mode
        let options: [String: Bool] = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Show an alert that guides the user to grant Accessibility permission.
    public func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Scroll Capture needs Accessibility access to scroll windows programmatically.\n\nPlease go to System Settings → Privacy & Security → Accessibility and enable BerryShot."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    /// Open the Accessibility section in System Settings/Preferences.
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
