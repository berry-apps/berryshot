import Cocoa
import Carbon

@MainActor
public class HotkeyManager {
    public static let shared = HotkeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
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
        let shortcut = currentShortcut
        
        // Unregister old
        unregister()
        
        // Register Carbon Hotkey
        let hotKeyID = EventHotKeyID(signature: OSType("bshT".utf8.reduce(0) { $0 << 8 | OSType($1) }), id: 1)
        
        var carbonModifiers: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags)
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        
        RegisterEventHotKey(UInt32(shortcut.keyCode), carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        // Install Event Handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            Task { @MainActor in
                HotkeyManager.shared.onCaptureHotkey?()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        
        // Fallback for local events (when app is active)
        let mask: NSEvent.EventTypeMask = .keyDown
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let currentFlags = event.modifierFlags.intersection([.command, .shift, .control, .option])
            let requiredFlags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags).intersection([.command, .shift, .control, .option])
            
            if currentFlags == requiredFlags && event.keyCode == shortcut.keyCode {
                self?.onCaptureHotkey?()
                return nil
            }
            return event
        }
    }
    
    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
    }
}
