import Cocoa
import SwiftUI
import Combine

public class OverlayWindowController: NSWindowController, NSWindowDelegate {
    internal var viewModel: OverlayViewModel!
    var toolbarController: ToolbarWindowController?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var interactModeCancellable: AnyCancellable?
    
    public convenience init(cgImage: CGImage, display: NSScreen) {
        let window = OverlayWindow(contentRect: display.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let viewModel = OverlayViewModel(
            cgImage: cgImage,
            onComplete: { renderedImage, selectedRect, redactionRegions in
                Task { @MainActor in
                    CaptureCoordinator.shared.finishCapture(cgImage: renderedImage, rect: selectedRect, redactionRegions: redactionRegions)
                }
            },
            onCopy: { renderedImage, selectedRect in
                Task { @MainActor in
                    CaptureCoordinator.shared.copyToClipboard(cgImage: renderedImage, rect: selectedRect)
                }
            },
            onUpload: { renderedImage, selectedRect, redactionRegions in
                Task { @MainActor in
                    CaptureCoordinator.shared.uploadCapture(cgImage: renderedImage, rect: selectedRect, redactionRegions: redactionRegions)
                }
            },
            onSaveAs: { renderedImage, selectedRect, redactionRegions in
                Task { @MainActor in
                    await CaptureCoordinator.shared.saveAsCapture(cgImage: renderedImage, rect: selectedRect, redactionRegions: redactionRegions)
                }
            }
        )
        
        let overlayView = OverlayView(viewModel: viewModel)
        let trackingView = TrackingHostingView(rootView: overlayView)
        trackingView.viewModel = viewModel
        
        window.contentView = trackingView
        window.viewModel = viewModel
        
        self.init(window: window)
        self.viewModel = viewModel
        viewModel.parentWindow = window
        window.delegate = self
    }
    
    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyboardMonitors()
        
        toolbarController = ToolbarWindowController(viewModel: viewModel, screenBounds: window?.frame ?? .zero)
        toolbarController?.show()
        
        interactModeCancellable = Publishers.CombineLatest(viewModel.$isInteractMode, viewModel.$isRecording)
            .receive(on: RunLoop.main)
            .sink { [weak self] isInteract, isRecording in
                guard let self = self, let window = self.window else { return }
                if isInteract {
                    window.level = .floating // Lower level allows ignoresMouseEvents to work
                    window.ignoresMouseEvents = true
                } else if isRecording {
                    window.level = .floating // Lower level to allow click-through inside the cutout
                    window.ignoresMouseEvents = false // Keep false so hitTest can intercept select/pencil tools
                } else {
                    window.level = .screenSaver // High level to overlay everything
                    window.ignoresMouseEvents = false
                }
            }
    }
    
    public func hide() {
        interactModeCancellable?.cancel()
        interactModeCancellable = nil
        removeKeyboardMonitors()
        toolbarController?.hide()
        toolbarController = nil
        window?.orderOut(nil)
    }
    
    private func installKeyboardMonitors() {
        removeKeyboardMonitors()
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isVisible else { return event }
            if self.shouldIgnoreForTextPanel() { return event }
            if self.processKeyEvent(event) { return nil }
            return event
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isVisible else { return }
            // A global monitor only fires while ANOTHER app has keyboard focus.
            // Cmd+C/V/… must stay with that app (never hijack its clipboard);
            // only ESC is treated as "cancel the capture" from anywhere.
            guard event.keyCode == 53 else { return }
            if self.shouldIgnoreForTextPanel() { return }
            DispatchQueue.main.async {
                _ = self.processKeyEvent(event)
            }
        }
        if globalMonitor == nil {
            print("[BerryShot] Global keyboard monitor không khả dụng — bật Accessibility cho Terminal/app trong System Settings > Privacy & Security > Accessibility")
        }
    }
    
    private func removeKeyboardMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
    
    private func shouldIgnoreForTextPanel() -> Bool {
        if let keyWindow = NSApp.keyWindow, keyWindow !== window {
            return true
        }
        return false
    }
    
    @discardableResult
    private func processKeyEvent(_ event: NSEvent) -> Bool {
        // Interact mode: the keyboard belongs to the system/other windows.
        if viewModel.isInteractMode {
            return false
        }
        // While typing in the annotation text field only ESC is ours;
        // Cmd+C/V/… must reach the field editor, not the capture shortcuts.
        if viewModel.activeTextInput != nil {
            if event.keyCode == 53 {
                viewModel.handleEscape()
                return true
            }
            return false
        }
        if event.keyCode == 53 {
            print("[BerryShot] ESC detected")
            viewModel.handleEscape()
            return true
        }
        if event.modifierFlags.contains(.command) {
            let char = event.charactersIgnoringModifiers?.lowercased()
            if char == "c" {
                print("[BerryShot] Cmd+C detected")
                viewModel.handleCopy()
                return true
            } else if char == "z" {
                if event.modifierFlags.contains(.shift) {
                    viewModel.redo()
                } else {
                    viewModel.undo()
                }
                return true
            }
        }
        return false
    }
    
    public func windowWillClose(_ notification: Notification) {
        removeKeyboardMonitors()
        Task { @MainActor in
            CaptureCoordinator.shared.cancelCapture()
        }
    }
}

class OverlayWindow: NSWindow {
    weak var viewModel: OverlayViewModel?
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.title = "BerryShot Overlay"
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if let keyWindow = NSApp.keyWindow, keyWindow !== self {
                super.sendEvent(event)
                return
            }
            if handleKeyEvent(event) { return }
        }
        super.sendEvent(event)
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let keyWindow = NSApp.keyWindow, keyWindow !== self {
            return super.performKeyEquivalent(with: event)
        }
        if handleKeyEvent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
    
    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            viewModel?.handleEscape()
            return true
        }

        // Interact mode: keyboard follows the system; only "i" re-locks the overlay.
        if viewModel?.isInteractMode == true {
            if !event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "i" {
                viewModel?.isInteractMode = false
                return true
            }
            return false
        }

        // If typing in a text field, do not intercept tool selection shortcuts.
        // Route clipboard shortcuts to the field editor ourselves: as a menu-bar
        // (accessory) app there is no reliable Edit menu to dispatch them.
        if viewModel?.activeTextInput != nil {
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "v":
                    return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                case "c":
                    return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                case "x":
                    return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                case "a":
                    return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                case "z":
                    let selector = event.modifierFlags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
                    _ = NSApp.sendAction(selector, to: nil, from: nil)
                    return true
                default:
                    break
                }
            }
            return false
        }

        if event.modifierFlags.contains(.command) {
            let char = event.charactersIgnoringModifiers?.lowercased()
            if char == "c" {
                viewModel?.handleCopy()
                return true
            } else if char == "z" {
                if event.modifierFlags.contains(.shift) {
                    viewModel?.redo()
                } else {
                    viewModel?.undo()
                }
                return true
            } else if char == "s" {
                viewModel?.handleSaveAs()
                return true
            } else if char == "u" {
                viewModel?.handleUpload()
                return true
            } else if char == "i" {
                viewModel?.handleAIAnalysis()
                return true
            } else if char == "o" {
                viewModel?.openImage()
                return true
            } else if char == "r" {
                viewModel?.handleRecordToggle()
                return true
            } else if char == "p" {
                if let isRecording = viewModel?.isRecording, isRecording {
                    if let isPaused = viewModel?.isPaused {
                        if isPaused {
                            RecordingManager.shared.resumeRecording()
                            viewModel?.isPaused = false
                        } else {
                            RecordingManager.shared.pauseRecording()
                            viewModel?.isPaused = true
                        }
                    }
                }
                return true
            } else if char == "\r" || char == "\n" {
                viewModel?.handleComplete()
                return true
            }
        } else {
            let char = event.charactersIgnoringModifiers?.lowercased()
            switch char {
            case "v":
                viewModel?.selectTool(.select)
                return true
            case "b":
                viewModel?.selectTool(.pencil)
                return true
            case "m":
                viewModel?.selectTool(.rectangle)
                return true
            case "c":
                viewModel?.selectTool(.circle)
                return true
            case "a":
                viewModel?.selectTool(.arrow)
                return true
            case "l":
                viewModel?.selectTool(.line)
                return true
            case "t":
                viewModel?.selectTool(.text)
                return true
            case "o":
                viewModel?.openImage()
                return true
            case "f":
                viewModel?.isFilled.toggle()
                return true
            case "i":
                viewModel?.isInteractMode.toggle()
                return true
            case "r":
                viewModel?.handleRecordToggle()
                return true
            case "p":
                if let isRecording = viewModel?.isRecording, isRecording {
                    if let isPaused = viewModel?.isPaused {
                        if isPaused {
                            RecordingManager.shared.resumeRecording()
                            viewModel?.isPaused = false
                        } else {
                            RecordingManager.shared.pauseRecording()
                            viewModel?.isPaused = true
                        }
                    }
                }
                return true
            case "h":
                viewModel?.showHelpPopover.toggle()
                return true
            case "\r", "\n":
                viewModel?.handleComplete()
                return true
            default:
                break
            }
        }
        return false
    }
}

class TrackingHostingView<Content: SwiftUI.View>: NSHostingView<Content> {
    weak var viewModel: OverlayViewModel?
    private var dragStart: CGPoint?
    private var dragDidStart = false
    private var pushedCursor: NSCursor?
    
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    override func resetCursorRects() {
        // Do nothing to prevent NSHostingView from setting default arrow cursor
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = locationInView(event)
        
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
        
        window?.makeFirstResponder(self)
        dragStart = point
        dragDidStart = true
        let isShiftPressed = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
        viewModel?.dragChanged(start: point, location: point, translation: .zero, isShiftPressed: isShiftPressed)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = locationInView(event)
        let translation = CGSize(width: point.x - start.x, height: point.y - start.y)
        let isShiftPressed = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
        viewModel?.dragChanged(start: start, location: point, translation: translation, isShiftPressed: isShiftPressed)
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = locationInView(event)
        if dragDidStart {
            let isShiftPressed = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            viewModel?.dragChanged(start: dragStart ?? point, location: point, translation: CGSize(width: point.x - (dragStart?.x ?? point.x), height: point.y - (dragStart?.y ?? point.y)), isShiftPressed: isShiftPressed)
            viewModel?.dragEnded(at: point, isShiftPressed: isShiftPressed)
        }
        dragStart = nil
        dragDidStart = false
    }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        
        // If the mouse is over the toolbar window, let the toolbar window handle its own cursors/hover.
        if let controller = self.window?.windowController as? OverlayWindowController,
           let toolbar = controller.toolbarController?.window, toolbar.isVisible {
            let mouseLocation = NSEvent.mouseLocation
            if toolbar.frame.contains(mouseLocation) {
                pushedCursor = nil
                return
            }
        }
        
        let point = locationInView(event)
        viewModel?.updateHover(at: point)
        
        if let newCursor = viewModel?.currentCursor {
            if pushedCursor != newCursor {
                newCursor.set()
                pushedCursor = newCursor
            }
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        viewModel?.endHover()
        pushedCursor = nil
    }
    
    override func keyDown(with event: NSEvent) {
        if let window = window as? OverlayWindow, window.handleKeyEvent(event) { return }
        super.keyDown(with: event)
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let window = window as? OverlayWindow, window.handleKeyEvent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        if viewModel?.isInteractMode == true {
            return nil
        }
        
        if let vm = viewModel, vm.isRecording, vm.selectedTool == .select {
            // Convert NSPoint (bottom-left) to SwiftUI point (top-left)
            let swiftUIPoint = CGPoint(x: point.x, y: bounds.height - point.y)
            
            // Is it over an annotation?
            if vm.elementAt(point: swiftUIPoint) != nil {
                return super.hitTest(point) ?? self
            }
            // Is it over a selection handle? (To allow resizing the recording area)
            if vm.getHandle(at: swiftUIPoint) != nil {
                return super.hitTest(point) ?? self
            }
            
            // Allow clicking through to underlying apps!
            return nil
        }
        
        let hit = super.hitTest(point)
        return hit ?? self
    }
    
    private func locationInView(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: p.y)
    }
}
