import Cocoa
import SwiftUI

public class AIResultWindowController: NSWindowController {
    public let viewModel = AIResultViewModel()
    
    public var onClose: (() -> Void)?
    
    public convenience init(rect: CGRect, screenBounds: CGRect) {
        let size = CGSize(width: 400, height: 500)
        let margin: CGFloat = 16
        
        var x = rect.maxX + margin
        if x + size.width > screenBounds.width {
            x = rect.maxX - size.width - margin
            if x < margin { x = margin }
        }
        
        var y = screenBounds.height - rect.minY - size.height
        if y < margin { y = margin }
        if y + size.height > screenBounds.height - margin { y = screenBounds.height - size.height - margin }
        
        let windowRect = NSRect(x: screenBounds.minX + x, y: screenBounds.minY + y, width: size.width, height: size.height)
        
        let window = AIResultWindow(
            contentRect: windowRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        
        self.init(window: window)
        
        let hostingView = AIResultHostingView(rootView: AIResultView(viewModel: viewModel, onClose: { [weak self] in
            self?.onClose?()
            self?.hide()
            self?.close()
        }))
        window.contentView = hostingView
    }
    
    public func show() {
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public override func close() {
        self.window?.orderOut(nil)
        self.window?.close()
        super.close()
    }
    
    public func hide() {
        self.window?.orderOut(nil)
    }
}

class AIResultWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AIResultHostingView<Content: SwiftUI.View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
