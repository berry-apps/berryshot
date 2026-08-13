import Cocoa
import SwiftUI

@MainActor
public class ToolbarWindowController: NSWindowController, NSWindowDelegate {
    var viewModel: OverlayViewModel!
    var screenBounds: CGRect = .zero
    public var isDragging: Bool = false
    // `nonisolated(unsafe)` only so `deinit` (always nonisolated, and
    // Timer isn't Sendable) can invalidate it directly as a last-resort
    // backstop. Safe here specifically because deinit only ever runs once
    // there are zero other references to this instance, so there is no
    // concurrent access to race with.
    private nonisolated(unsafe) var positionTimer: Timer?
    
    convenience init(viewModel: OverlayViewModel, screenBounds: CGRect) {
        let size = CGSize(width: 440, height: 120)
        let pos = viewModel.toolbarPosition(for: viewModel.selectionRect, screenBounds: screenBounds)
        // Convert top-left (pos) to bottom-left for NSWindow
        let bottomY = screenBounds.height - pos.y
        let windowRect = NSRect(x: screenBounds.minX + pos.x - size.width / 2,
                                y: screenBounds.minY + bottomY - size.height / 2,
                                width: size.width, height: size.height)
        
        let window = ToolbarWindow(contentRect: windowRect, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        self.init(window: window)
        window.delegate = self
        self.viewModel = viewModel
        self.screenBounds = screenBounds
        
        let toolbarView = ToolbarWindowView(viewModel: viewModel, screenBounds: screenBounds)
        let hostingView = ToolbarHostingView(rootView: toolbarView)
        window.contentView = hostingView
        
        // Sync initial toolbar size
        viewModel.toolbarSize = window.frame.size
    }
    
    override init(window: NSWindow?) {
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show() {
        window?.makeKeyAndOrderFront(nil)

        // Update position loop. A fresh `ToolbarWindowController` (and thus a
        // fresh timer) is created for every single capture session — this
        // one was never stored or invalidated, so `hide()` released the
        // controller while the timer itself, retained by the run loop, kept
        // firing at 20Hz forever. Every capture taken over a session left
        // behind one more permanent background timer running indefinitely.
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let window = self.window, let vm = self.viewModel else { return }
                
                // If the user is currently dragging the window naturally, don't force it back!
                if self.isDragging { return }
                
                let pos = vm.toolbarPosition(for: vm.selectionRect, screenBounds: self.screenBounds)
                let bottomY = self.screenBounds.height - pos.y
                
                // Use the fitting size of contentView if available, falling back to current frame size
                let fittingSize = window.contentView?.fittingSize ?? window.frame.size
                let size = vm.isToolbarCollapsed ? CGSize(width: 44, height: 44) : fittingSize
                
                let newRect = NSRect(
                    x: self.screenBounds.minX + pos.x - size.width / 2,
                    y: self.screenBounds.minY + bottomY - size.height / 2,
                    width: size.width, height: size.height
                )
                
                // Only snap to newRect if there is a significant (>= 0.5 points) difference
                // to avoid sub-pixel rounding jitter or coordinate feedback loop.
                let dx = abs(window.frame.origin.x - newRect.origin.x)
                let dy = abs(window.frame.origin.y - newRect.origin.y)
                let dw = abs(window.frame.size.width - newRect.size.width)
                let dh = abs(window.frame.size.height - newRect.size.height)
                
                if dx > 0.5 || dy > 0.5 || dw > 0.5 || dh > 0.5 {
                    window.setFrame(newRect, display: true, animate: false)
                }
            }
        }
    }
    
    public func hide() {
        window?.orderOut(nil)
        positionTimer?.invalidate()
        positionTimer = nil
    }

    // Backstop for any future exit path that drops this controller without
    // calling `hide()` first — without this, that path would silently
    // resurrect the exact unbounded 20Hz-timer leak `positionTimer` fixes.
    deinit {
        positionTimer?.invalidate()
    }
    
    public func windowDidMove(_ notification: Notification) {
        guard let window = self.window, let vm = self.viewModel, isDragging else { return }
        let pos = CGPoint(x: window.frame.midX - self.screenBounds.minX,
                          y: self.screenBounds.height - (window.frame.midY - self.screenBounds.minY))
        vm.customToolbarPosition = pos
        vm.toolbarSize = window.frame.size
    }
    
    public func windowDidResize(_ notification: Notification) {
        guard let window = self.window, let vm = self.viewModel else { return }
        vm.toolbarSize = window.frame.size
    }
}

class ToolbarWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class ToolbarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func resetCursorRects() {
        // Do nothing to prevent NSHostingView from setting default arrow cursor
    }
    
    override func mouseDown(with event: NSEvent) {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
        super.mouseDown(with: event)
    }
}

struct ToolbarWindowView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let screenBounds: CGRect
    @State private var showColorPicker: Bool = false
    
    var body: some View {
        if viewModel.isSelectingFinished {
            ToolbarView(viewModel: viewModel, showColorPicker: $showColorPicker, screenBounds: screenBounds)
        }
    }
}
