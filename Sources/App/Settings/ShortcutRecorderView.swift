import SwiftUI
import Cocoa

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    var defaultsKey: String = "captureShortcut"

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        let key = defaultsKey
        view.onShortcutChanged = { newShortcut in
            shortcut = newShortcut
            if let encoded = try? JSONEncoder().encode(newShortcut) {
                UserDefaults.standard.set(encoded, forKey: key)
                HotkeyManager.shared.reloadHotkeys()
            }
        }
        view.shortcut = shortcut
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.shortcut = shortcut
    }
}

class ShortcutRecorderNSView: NSView {
    var onShortcutChanged: ((Shortcut) -> Void)?
    
    var shortcut: Shortcut? {
        didSet {
            needsDisplay = true
        }
    }
    
    private var isRecording = false {
        didSet {
            needsDisplay = true
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        let roundedRect = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        
        if isRecording {
            NSColor.controlAccentColor.setStroke()
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
        } else {
            NSColor.gridColor.setStroke()
            NSColor.controlBackgroundColor.setFill()
        }
        
        roundedRect.fill()
        roundedRect.lineWidth = 1
        roundedRect.stroke()
        
        let displayString = isRecording ? "Press new shortcut..." : (shortcut?.displayString ?? "None")
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let size = displayString.size(withAttributes: attributes)
        let textRect = NSRect(x: 0, y: (bounds.height - size.height) / 2 - 1, width: bounds.width, height: size.height)
        displayString.draw(in: textRect, withAttributes: attributes)
    }
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }
    
    override func keyDown(with event: NSEvent) {
        if !isRecording {
            super.keyDown(with: event)
            return
        }
        
        let modifierFlags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        
        if event.keyCode == 53 { // Esc to cancel
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }
        
        if !modifierFlags.isEmpty {
            let newShortcut = Shortcut(keyCode: event.keyCode, modifierFlags: modifierFlags.rawValue)
            onShortcutChanged?(newShortcut)
            isRecording = false
            window?.makeFirstResponder(nil)
        }
    }
}
