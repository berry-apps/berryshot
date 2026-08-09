import Foundation
import Cocoa
import SwiftUI

public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifierFlags: UInt

    public init(keyCode: UInt16, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
    
    public static let defaultShortcut = Shortcut(
        keyCode: 19, // 2
        modifierFlags: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
    )

    public static let defaultScrollShortcut = Shortcut(
        keyCode: 28, // 8
        modifierFlags: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
    )

    public static let defaultAppWindowCaptureShortcut = Shortcut(
        keyCode: 26, // 7 — avoids both the other in-app defaults (2, 8) and
        // macOS's own reserved Cmd+Shift+3/4/5/6 screenshot shortcuts.
        modifierFlags: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
    )
    
    public var displayString: String {
        var str = ""
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        if flags.contains(.control) { str += "⌃" }
        if flags.contains(.option) { str += "⌥" }
        if flags.contains(.shift) { str += "⇧" }
        if flags.contains(.command) { str += "⌘" }
        
        let keyString = KeycodeHelper.string(for: keyCode)
        return str + keyString
    }
    
    public var swiftuiKeyEquivalent: KeyEquivalent? {
        let str = KeycodeHelper.string(for: keyCode).lowercased()
        if str.count == 1, let char = str.first {
            return KeyEquivalent(char)
        }
        return nil
    }
    
    public var swiftuiModifiers: EventModifiers {
        var mods = EventModifiers()
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        return mods
    }
}

/// Where the floating annotation toolbar defaults to, relative to the
/// active capture selection — persisted at UserDefaults key
/// "toolbarPosition". Overridden per-capture the moment the user manually
/// drags the toolbar (`OverlayViewModel.customToolbarPosition`).
public enum ToolbarPosition: String, CaseIterable {
    case top, left, right, bottom

    public var displayName: String {
        switch self {
        case .top: return "Top"
        case .left: return "Left"
        case .right: return "Right"
        case .bottom: return "Bottom"
        }
    }
}

public class KeycodeHelper {
    public static func string(for keyCode: UInt16) -> String {
        // Basic mapping for common keys
        let map: [UInt16: String] = [
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            53: "Esc", 49: "Space", 36: "Return", 51: "Delete", 48: "Tab",
            123: "←", 124: "→", 126: "↑", 125: "↓"
        ]
        return map[keyCode] ?? "?"
    }
}
