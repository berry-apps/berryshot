import SwiftUI
import AppKit

struct WindowDragOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> CustomDragNSView {
        return CustomDragNSView()
    }
    
    func updateNSView(_ nsView: CustomDragNSView, context: Context) {}
}

@MainActor
class CustomDragNSView: NSView {
    private var startOrigin: NSPoint?
    private var startMouseGlobal: NSPoint?
    private var trackingArea: NSTrackingArea?
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        let options: NSTrackingArea.Options = [.cursorUpdate, .activeAlways]
        let newArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
    }
    
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.openHand.set()
    }
    
    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        startOrigin = window.frame.origin
        startMouseGlobal = NSEvent.mouseLocation
        if let controller = window.windowController as? ToolbarWindowController {
            controller.isDragging = true
        }
        NSCursor.closedHand.push()
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window,
              let startOrigin = startOrigin,
              let startMouseGlobal = startMouseGlobal else { return }
        
        let currentMouseGlobal = NSEvent.mouseLocation
        let deltaX = currentMouseGlobal.x - startMouseGlobal.x
        let deltaY = currentMouseGlobal.y - startMouseGlobal.y
        
        let newOrigin = NSPoint(x: startOrigin.x + deltaX, y: startOrigin.y + deltaY)
        window.setFrameOrigin(newOrigin)
        
        if let controller = window.windowController as? ToolbarWindowController,
           let vm = controller.viewModel {
            let midX = newOrigin.x + window.frame.size.width / 2
            let midY = newOrigin.y + window.frame.size.height / 2
            let pos = CGPoint(x: midX - controller.screenBounds.minX,
                              y: controller.screenBounds.height - (midY - controller.screenBounds.minY))
            vm.customToolbarPosition = pos
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let window = self.window else { return }
        
        if let controller = window.windowController as? ToolbarWindowController,
           let vm = controller.viewModel {
            let midX = window.frame.midX
            let midY = window.frame.midY
            let pos = CGPoint(x: midX - controller.screenBounds.minX,
                              y: controller.screenBounds.height - (midY - controller.screenBounds.minY))
            vm.customToolbarPosition = pos
            controller.isDragging = false
        } else if let controller = window.windowController as? ToolbarWindowController {
            controller.isDragging = false
        }
        
        startOrigin = nil
        startMouseGlobal = nil
        NSCursor.pop()
    }
}
