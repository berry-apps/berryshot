import Cocoa
import Carbon

@MainActor
public class HotkeyManager {
    public static let shared = HotkeyManager()

    private var captureHotKeyRef: EventHotKeyRef?
    private var scrollHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var localMonitor: Any?

    public var onCaptureHotkey: (() -> Void)?
    public var onScrollCaptureHotkey: (() -> Void)?

    private init() {}

    private static let captureHotKeyID: UInt32 = 1
    private static let scrollHotKeyID: UInt32 = 2

    private var signature: OSType {
        OSType("bshT".utf8.reduce(0) { $0 << 8 | OSType($1) })
    }

    private func shortcut(forKey key: String, fallback: Shortcut) -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return decoded
        }
        return fallback
    }

    private var captureShortcut: Shortcut {
        shortcut(forKey: "captureShortcut", fallback: .defaultShortcut)
    }

    private var scrollShortcut: Shortcut {
        shortcut(forKey: "scrollCaptureShortcut", fallback: .defaultScrollShortcut)
    }

    private func carbonModifiers(for shortcut: Shortcut) -> UInt32 {
        var mods: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags)
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    public func reloadHotkeys() {
        unregister()
        registerHotkeys()
    }

    public func registerHotkeys() {
        // Unregister old
        unregister()

        let capture = captureShortcut
        let scroll = scrollShortcut

        // Register Carbon hotkeys (global, work even when app is in background)
        let captureID = EventHotKeyID(signature: signature, id: Self.captureHotKeyID)
        RegisterEventHotKey(UInt32(capture.keyCode), carbonModifiers(for: capture), captureID, GetApplicationEventTarget(), 0, &captureHotKeyRef)

        let scrollID = EventHotKeyID(signature: signature, id: Self.scrollHotKeyID)
        RegisterEventHotKey(UInt32(scroll.keyCode), carbonModifiers(for: scroll), scrollID, GetApplicationEventTarget(), 0, &scrollHotKeyRef)

        // Install a single event handler that dispatches by hotkey id
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { (_, theEvent, _) -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(theEvent,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            let id = hkID.id
            Task { @MainActor in
                if id == HotkeyManager.captureHotKeyID {
                    HotkeyManager.shared.onCaptureHotkey?()
                } else if id == HotkeyManager.scrollHotKeyID {
                    HotkeyManager.shared.onScrollCaptureHotkey?()
                }
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)

        // Fallback for local events (when app is active)
        let mask: NSEvent.EventTypeMask = .keyDown
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            let currentFlags = event.modifierFlags.intersection([.command, .shift, .control, .option])

            func matches(_ shortcut: Shortcut) -> Bool {
                let required = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags).intersection([.command, .shift, .control, .option])
                return currentFlags == required && event.keyCode == shortcut.keyCode
            }

            if matches(capture) {
                self.onCaptureHotkey?()
                return nil
            }
            if matches(scroll) {
                self.onScrollCaptureHotkey?()
                return nil
            }
            return event
        }
    }

    public func unregister() {
        if let ref = captureHotKeyRef {
            UnregisterEventHotKey(ref)
            captureHotKeyRef = nil
        }
        if let ref = scrollHotKeyRef {
            UnregisterEventHotKey(ref)
            scrollHotKeyRef = nil
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
