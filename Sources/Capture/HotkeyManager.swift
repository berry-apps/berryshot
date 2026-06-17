import Cocoa

@MainActor
public class HotkeyManager {
    public static let shared = HotkeyManager()
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    public var onCaptureHotkey: (() -> Void)?
    
    private init() {}
    
    private var currentShortcut: Shortcut {
        if let data = UserDefaults.standard.data(forKey: "captureShortcut"),
           let decoded = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return decoded
        }
        return Shortcut.defaultShortcut
    }
    
    public func reloadHotkeys() {
        unregister()
        registerHotkeys()
    }

    public func registerHotkeys() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("Accessibility permission not granted. Hotkeys will not work globally.")
        }
        
        let mask: NSEvent.EventTypeMask = .keyDown
        let shortcut = currentShortcut
        
        let handler: (NSEvent) -> Void = { [weak self] event in
            // Clean up modifier flags to only care about the main ones
            let currentFlags = event.modifierFlags.intersection([.command, .shift, .control, .option])
            let requiredFlags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags).intersection([.command, .shift, .control, .option])
            
            if currentFlags == requiredFlags && event.keyCode == shortcut.keyCode {
                self?.onCaptureHotkey?()
            }
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            handler(event)
            return event
        }
    }
    
    public func unregister() {
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
    }
}
