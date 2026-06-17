import SwiftUI
import CoreGraphics
import Cocoa

enum DragMode {
    case selecting(start: CGPoint)
    case resizing(Handle, originalRect: CGRect)
    case annotating
    case movingElement(UUID, original: AnnotationElement)
    case editingPoint(elementId: UUID, pointIndex: Int, original: AnnotationElement)
    case movingSelection(originalRect: CGRect, elementsSnapshot: [AnnotationElement])
    case none
}

enum Handle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

@MainActor
final class OverlayViewModel: ObservableObject {
    let cgImage: CGImage
    let onComplete: (CGImage, CGRect) -> Void
    let onCopy: (CGImage, CGRect) -> Void
    let onUpload: (CGImage, CGRect) -> Void
    
    @Published var selectionRect: CGRect = .zero
    @Published var isSelectingFinished = false
    @Published var dragMode: DragMode = .none
    
    @Published var selectedTool: AnnotationToolType = .select
    @Published var currentCursor: NSCursor = .arrow
    @Published var selectedColor: Color = .red {
        didSet {
            if let id = selectedElementID, let idx = elements.firstIndex(where: { $0.id == id }) {
                saveState()
                elements[idx].color = selectedColor
            }
        }
    }
    @Published var isFilled: Bool = false {
        didSet {
            if let id = selectedElementID, let idx = elements.firstIndex(where: { $0.id == id }) {
                saveState()
                elements[idx].isFilled = isFilled
            }
        }
    }
    @Published var fillOpacity: CGFloat = 0.4 {
        didSet {
            if let id = selectedElementID, let idx = elements.firstIndex(where: { $0.id == id }) {
                saveState()
                elements[idx].fillOpacity = fillOpacity
            }
        }
    }
    
    @Published var selectedFontSize: CGFloat = 24 {
        didSet {
            if let id = selectedElementID, let idx = elements.firstIndex(where: { $0.id == id }) {
                saveState()
                elements[idx].fontSize = selectedFontSize
            }
        }
    }
    @Published var hoveredElementID: UUID? = nil
    
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var isProcessingRecord = false
    
    @Published var elements: [AnnotationElement] = []
    @Published var currentElement: AnnotationElement? = nil
    @Published var selectedElementID: UUID? = nil
    
    struct HistoryState {
        let elements: [AnnotationElement]
        let selectionRect: CGRect
    }
    private var undoStack: [HistoryState] = []
    private var redoStack: [HistoryState] = []
    
    @Published var snappedPoint: CGPoint? = nil
    @Published var snappedBinding: BindingAnchor? = nil
    @Published var cachedGeometrySize: CGSize = .zero
    
    struct TextInputState: Equatable {
        var position: CGPoint
        var text: String
        var elementID: UUID?
        var bounds: CGRect
        var fontSize: CGFloat
    }
    
    @Published var activeTextInput: TextInputState? = nil
    weak var parentWindow: NSWindow?
    private var localEventMonitor: Any?
    
    private var lastClickTime: Date = .distantPast
    private var lastClickLocation: CGPoint = .zero
    
    let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
    
    init(cgImage: CGImage, onComplete: @escaping (CGImage, CGRect) -> Void, onCopy: @escaping (CGImage, CGRect) -> Void, onUpload: @escaping (CGImage, CGRect) -> Void) {
        self.cgImage = cgImage
        self.onComplete = onComplete
        self.onCopy = onCopy
        self.onUpload = onUpload
    }
    
    func setupEventMonitor() {
        guard localEventMonitor == nil else { return }
        self.localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.activeTextInput == nil {
                if event.keyCode == 51 || event.keyCode == 117 {
                    self.deleteSelectedElement()
                    return nil
                } else if event.keyCode == 36 { // Enter key
                    if let id = self.selectedElementID, let el = self.elements.first(where: { $0.id == id }), el.type != .select {
                        let center = CGPoint(x: el.shapeRect().midX, y: el.shapeRect().midY)
                        self.activeTextInput = TextInputState(
                            position: center,
                            text: el.text,
                            elementID: el.id,
                            bounds: el.type == .text ? el.shapeRect() : CGRect(x: center.x - (el.shapeRect().width * 0.75) / 2, y: center.y - (el.shapeRect().height * 0.75) / 2, width: el.shapeRect().width * 0.75, height: el.shapeRect().height * 0.75),
                            fontSize: el.type == .text ? (el.shapeRect().height / 1.2) : (el.shapeRect().height / 5.33)
                        )
                        return nil
                    }
                } else if event.modifierFlags.contains(.command) && event.keyCode == 6 { // Cmd+Z
                    if event.modifierFlags.contains(.shift) {
                        self.redo()
                    } else {
                        self.undo()
                    }
                    return nil
                }
            }
            return event
        }
    }
    
    private func saveState() {
        undoStack.append(HistoryState(elements: elements, selectionRect: selectionRect))
        redoStack.removeAll()
    }
    
    func undo() {
        guard let prevState = undoStack.popLast() else { return }
        redoStack.append(HistoryState(elements: elements, selectionRect: selectionRect))
        elements = prevState.elements
        selectionRect = prevState.selectionRect
        selectedElementID = nil
        activeTextInput = nil
    }
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    @Published var isToolbarCollapsed = false
    @Published var isInteractMode = false
    @Published var showHelpPopover = false
    
    @Published var customToolbarPosition: CGPoint? = nil
    @Published var toolbarSize: CGSize = CGSize(width: 440, height: 120)
    
    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
                let imageSize = image.size
                
                var maxWidth = self.selectionRect.width > 40 ? self.selectionRect.width - 40 : self.selectionRect.width
                var maxHeight = self.selectionRect.height > 40 ? self.selectionRect.height - 40 : self.selectionRect.height
                if maxWidth <= 0 { maxWidth = 300 }
                if maxHeight <= 0 { maxHeight = 300 }
                
                let scaleX = maxWidth / max(imageSize.width, 1)
                let scaleY = maxHeight / max(imageSize.height, 1)
                let scale = min(1.0, min(scaleX, scaleY))
                
                let defaultWidth = imageSize.width * scale
                let defaultHeight = imageSize.height * scale
                
                var cx = self.selectionRect.midX
                var cy = self.selectionRect.midY
                if self.selectionRect == .zero || self.selectionRect.width == 0 {
                    cx = 200
                    cy = 200
                }
                
                let startPoint = CGPoint(x: cx - defaultWidth / 2, y: cy - defaultHeight / 2)
                let endPoint = CGPoint(x: cx + defaultWidth / 2, y: cy + defaultHeight / 2)
                
                var element = AnnotationElement(type: .image, startPoint: startPoint, nsImage: image)
                element.endPoint = endPoint
                element.rebuildPath()
                
                self.saveState()
                self.elements.append(element)
                self.selectedElementID = element.id
                self.selectedTool = .select
            }
        }
        
        if let parent = self.parentWindow {
            panel.beginSheetModal(for: parent, completionHandler: handler)
        } else {
            panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            let response = panel.runModal()
            handler(response)
        }
    }
    
    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(HistoryState(elements: elements, selectionRect: selectionRect))
        elements = nextState.elements
        selectionRect = nextState.selectionRect
        selectedElementID = nil
        activeTextInput = nil
    }
    
    func removeEventMonitor() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    var isConnectorTool: Bool {
        selectedTool == .line || selectedTool == .arrow
    }
    
    var showsAllBindingPoints: Bool {
        isConnectorTool || hoveredElementID != nil
    }
    
    func bindingPointItems() -> [(elementId: UUID, index: Int, point: CGPoint, isConnector: Bool)] {
        var items: [(UUID, Int, CGPoint, Bool)] = []
        
        if isConnectorTool {
            for element in elements where element.hasBindingPoints {
                for (idx, pt) in element.bindingPoints.enumerated() {
                    items.append((element.id, idx, pt, false))
                }
            }
            return items
        }
        
        if let id = selectedElementID, let element = elements.first(where: { $0.id == id }), element.hasBindingPoints {
            let isHovered = (id == hoveredElementID)
            let isLine = element.type == .line || element.type == .arrow
            for (idx, pt) in element.bindingPoints.enumerated() {
                // If hovered and not a line, hide the edge resize handles (4,5,6,7) to make room for connector pluses
                if isHovered && !isLine && (idx >= 4) { continue }
                items.append((id, idx, pt, false))
            }
        }
        
        if let id = hoveredElementID, let element = elements.first(where: { $0.id == id }) {
            for (idx, pt) in element.connectorHandles.enumerated() {
                items.append((id, idx, pt, true))
            }
        }
        
        return items
    }
    
    func handleEscape() {
        if activeTextInput != nil {
            activeTextInput = nil
            return
        }
        
        if selectedTool != .select || selectedElementID != nil {
            selectedTool = .select
            selectedElementID = nil
            return
        }
        
        CaptureCoordinator.shared.cancelCapture()
        parentWindow?.close()
    }
    
    func handleCopy() {
        commitActiveText()
        if let rendered = renderAnnotatedImage() {
            onCopy(rendered, selectionRect)
        } else {
            onCopy(cgImage, selectionRect)
        }
    }
    
    func handleComplete() {
        commitActiveText()
        if let rendered = renderAnnotatedImage() {
            onComplete(rendered, selectionRect)
        } else {
            onComplete(cgImage, selectionRect)
        }
    }
    
    func handleUpload() {
        commitActiveText()
        if let rendered = renderAnnotatedImage() {
            onUpload(rendered, selectionRect)
        } else {
            onUpload(cgImage, selectionRect)
        }
    }
    
    func handleCancel() {
        CaptureCoordinator.shared.cancelCapture()
        parentWindow?.close()
    }
    
    var isDrawingTool: Bool {
        switch selectedTool {
        case .select: return false
        default: return true
        }
    }
    
    func selectTool(_ tool: AnnotationToolType) {
        commitActiveText()
        if selectedTool == tool && tool != .select {
            selectedTool = .select
        } else {
            selectedTool = tool
        }
        if selectedTool != .select && selectedTool != .line && selectedTool != .arrow {
            selectedElementID = nil
        }
    }
    
    func getHandle(at point: CGPoint) -> Handle? {
        let r: CGFloat = 12
        let rect = selectionRect
        
        if abs(point.x - rect.minX) < r && abs(point.y - rect.minY) < r { return .topLeft }
        if abs(point.x - rect.maxX) < r && abs(point.y - rect.minY) < r { return .topRight }
        if abs(point.x - rect.minX) < r && abs(point.y - rect.maxY) < r { return .bottomLeft }
        if abs(point.x - rect.maxX) < r && abs(point.y - rect.maxY) < r { return .bottomRight }
        
        if abs(point.y - rect.minY) < r && point.x > rect.minX && point.x < rect.maxX { return .top }
        if abs(point.y - rect.maxY) < r && point.x > rect.minX && point.x < rect.maxX { return .bottom }
        if abs(point.x - rect.minX) < r && point.y > rect.minY && point.y < rect.maxY { return .left }
        if abs(point.x - rect.maxX) < r && point.y > rect.minY && point.y < rect.maxY { return .right }
        
        return nil
    }
    
    func deleteElement(id: UUID) {
        saveState()
        if let idx = elements.firstIndex(where: { $0.id == id }) {
            elements.remove(at: idx)
            if selectedElementID == id {
                selectedElementID = nil
            }
            refreshBoundConnectors()
        }
    }
    
    func bringToFront(elementId: UUID) {
        saveState()
        if let idx = elements.firstIndex(where: { $0.id == elementId }) {
            let el = elements.remove(at: idx)
            elements.append(el)
        }
    }
    
    func sendToBack(elementId: UUID) {
        saveState()
        if let idx = elements.firstIndex(where: { $0.id == elementId }) {
            let el = elements.remove(at: idx)
            elements.insert(el, at: 0)
        }
    }
    
    @objc func deleteSelectedElement() {
        if let id = selectedElementID {
            deleteElement(id: id)
        }
    }
    
    func elementAt(point: CGPoint) -> AnnotationElement? {
        elements.reversed().first { $0.contains(point: point) }
    }
    
    func findBinding(near point: CGPoint, excludingElementId: UUID? = nil) -> BindingSnapResult? {
        let snapThreshold: CGFloat = 18
        var best: BindingSnapResult?
        var minDistance = snapThreshold
        
        for element in elements where element.hasBindingPoints {
            if element.id == excludingElementId { continue }
            for (index, mPoint) in element.bindingPoints.enumerated() {
                let distance = hypot(mPoint.x - point.x, mPoint.y - point.y)
                if distance < minDistance {
                    minDistance = distance
                    best = BindingSnapResult(
                        point: mPoint,
                        anchor: BindingAnchor(elementId: element.id, pointIndex: index)
                    )
                }
            }
        }
        return best
    }
    
    func findSnapPoint(near point: CGPoint) -> CGPoint? {
        findBinding(near: point)?.point
    }
    
    func refreshBoundConnectors() {
        for i in elements.indices {
            guard elements[i].type == .line || elements[i].type == .arrow else { continue }
            var el = elements[i]
            var changed = false
            
            if let binding = el.startBinding,
               let source = elements.first(where: { $0.id == binding.elementId }),
               let pt = source.bindingPoint(at: binding.pointIndex) {
                el.startPoint = pt
                changed = true
            }
            if let binding = el.endBinding,
               let source = elements.first(where: { $0.id == binding.elementId }),
               let pt = source.bindingPoint(at: binding.pointIndex) {
                el.endPoint = pt
                changed = true
            }
            if changed {
                el.rebuildPath()
                elements[i] = el
            }
        }
    }
    
    private func applyStartBinding(to element: inout AnnotationElement, at point: CGPoint, snap: BindingSnapResult?) {
        if let snap {
            element.startPoint = snap.point
            element.startBinding = snap.anchor
        } else {
            element.startPoint = point
            element.startBinding = nil
        }
    }
    
    private func applyEndBinding(to element: inout AnnotationElement, at point: CGPoint, snap: BindingSnapResult?) {
        if let snap {
            element.endPoint = snap.point
            element.endBinding = snap.anchor
        } else {
            element.endPoint = point
            element.endBinding = nil
        }
        element.rebuildPath()
    }
    
    func updateHover(at location: CGPoint) {
        guard isSelectingFinished, activeTextInput == nil else { return }
        
        let screenBounds = CGRect(origin: .zero, size: cachedGeometrySize)
        if toolbarHitRect(screenBounds: screenBounds).contains(location) {
            if hoveredElementID != nil {
                hoveredElementID = nil
            }
            if let _ = snappedPoint {
                snappedPoint = nil
                snappedBinding = nil
            }
            currentCursor = .arrow
            return
        }
        
        var isInsideActionIcon = false
        if let id = selectedElementID, let el = elements.first(where: { $0.id == id }) {
            let cx = el.boundingRect.maxX + 20
            let cy = el.boundingRect.minY - 20
            let deleteRect = CGRect(x: cx - 15, y: cy - 15, width: 30, height: 30)
            let bringFrontRect = CGRect(x: cx + 26 - 15, y: cy - 15, width: 30, height: 30)
            let sendBackRect = CGRect(x: cx + 52 - 15, y: cy - 15, width: 30, height: 30)
            if deleteRect.contains(location) || bringFrontRect.contains(location) || sendBackRect.contains(location) {
                isInsideActionIcon = true
            }
        }
        
        if let hit = elementAt(point: location) {
            if hoveredElementID != hit.id { hoveredElementID = hit.id }
        } else {
            if hoveredElementID != nil { hoveredElementID = nil }
        }
        
        var isHoveringHandle = false
        var targetIds = Set<UUID>()
        if let id = selectedElementID { targetIds.insert(id) }
        if let id = hoveredElementID { targetIds.insert(id) }
        
        for id in targetIds {
            if let el = elements.first(where: { $0.id == id }) {
                for pt in el.connectorHandles {
                    if hypot(pt.x - location.x, pt.y - location.y) < 8 {
                        isHoveringHandle = true
                    }
                }
                if selectedTool == .select, selectedElementID == id {
                    for pt in el.bindingPoints {
                        if hypot(pt.x - location.x, pt.y - location.y) < 8 {
                            isHoveringHandle = true
                        }
                    }
                }
            }
        }
        
        var targetCursor: NSCursor? = nil
        
        if isInsideActionIcon {
            targetCursor = .pointingHand
            if snappedPoint != nil { snappedPoint = nil }
            if snappedBinding != nil { snappedBinding = nil }
        } else if getHandle(at: location) != nil {
            targetCursor = .crosshair
            if snappedPoint != nil { snappedPoint = nil }
            if snappedBinding != nil { snappedBinding = nil }
        } else if isHoveringHandle {
            targetCursor = .crosshair
            if snappedPoint != nil { snappedPoint = nil }
            if snappedBinding != nil { snappedBinding = nil }
        } else if isConnectorTool {
            targetCursor = .crosshair
            if let snap = findBinding(near: location) {
                if snappedPoint != snap.point { snappedPoint = snap.point }
                if snappedBinding != snap.anchor { snappedBinding = snap.anchor }
            } else {
                if snappedPoint != nil { snappedPoint = nil }
                if snappedBinding != nil { snappedBinding = nil }
            }
        } else if elementAt(point: location) != nil, selectedTool != .text {
            targetCursor = .openHand
            if snappedPoint != nil { snappedPoint = nil }
            if snappedBinding != nil { snappedBinding = nil }
        } else if selectedTool == .select, selectionRect.contains(location) {
            targetCursor = .openHand
            if snappedPoint != nil { snappedPoint = nil }
            if snappedBinding != nil { snappedBinding = nil }
        } else if isDrawingTool {
            targetCursor = .crosshair
            if let snap = findBinding(near: location) {
                if snappedPoint != snap.point { snappedPoint = snap.point }
                if snappedBinding != snap.anchor { snappedBinding = snap.anchor }
            } else {
                if snappedPoint != nil { snappedPoint = nil }
                if snappedBinding != nil { snappedBinding = nil }
            }
        } else {
            targetCursor = .crosshair
            if snappedPoint != nil { snappedPoint = nil }
            if snappedBinding != nil { snappedBinding = nil }
        }
        
        let newCursor = targetCursor ?? .arrow
        if currentCursor != newCursor {
            currentCursor = newCursor
        }
    }
    
    func endHover() {
        if currentCursor != .arrow {
            currentCursor = .arrow
        }
        hoveredElementID = nil
        snappedPoint = nil
        snappedBinding = nil
    }
    
    func dragChanged(start: CGPoint, location: CGPoint, translation: CGSize, isShiftPressed: Bool = false) {
        if let input = activeTextInput {
            if input.bounds.contains(start) {
                return
            }
            commitActiveText()
        }
        
        switch dragMode {
        case .none:
            if let id = selectedElementID, let el = elements.first(where: { $0.id == id }) {
                let cx = el.boundingRect.maxX + 35
                let cy = el.boundingRect.minY - 20
                
                let sendBackRect = CGRect(x: cx - 40, y: cy - 15, width: 26, height: 30)
                let bringFrontRect = CGRect(x: cx - 13, y: cy - 15, width: 26, height: 30)
                let trashRect = CGRect(x: cx + 14, y: cy - 15, width: 26, height: 30)
                
                if sendBackRect.contains(start) {
                    sendToBack(elementId: id)
                    return
                }
                if bringFrontRect.contains(start) {
                    bringToFront(elementId: id)
                    return
                }
                if trashRect.contains(start) {
                    deleteElement(id: id)
                    return
                }
            }
            
            if !isSelectingFinished {
                dragMode = .selecting(start: start)
                selectionRect = CGRect(x: start.x, y: start.y, width: 0, height: 0)
            } else {
                if let handle = getHandle(at: start) {
                    saveState()
                    dragMode = .resizing(handle, originalRect: selectionRect)
                } else {
                    var handledBindingPoint = false
                    
                    var targetIds = Set<UUID>()
                    if let id = selectedElementID { targetIds.insert(id) }
                    if let id = hoveredElementID { targetIds.insert(id) }
                    
                    outer: for targetId in targetIds {
                        if let el = elements.first(where: { $0.id == targetId }) {
                            for (cIdx, pt) in el.connectorHandles.enumerated() {
                                if hypot(pt.x - start.x, pt.y - start.y) < 8 {
                                    saveState()
                                    selectedTool = .arrow
                                    dragMode = .annotating
                                    let bIdx: Int
                                    if cIdx == 0 { bIdx = 4 }      // Top -> Top
                                    else if cIdx == 1 { bIdx = 6 } // Left -> Left
                                    else if cIdx == 2 { bIdx = 7 } // Right -> Right
                                    else { bIdx = 5 }              // Bottom -> Bottom
                                    
                                    let snapPt = el.bindingPoint(at: bIdx) ?? pt
                                    let startSnap = BindingSnapResult(point: snapPt, anchor: BindingAnchor(elementId: el.id, pointIndex: bIdx))
                                    var arrow = AnnotationElement(type: .arrow, startPoint: snapPt, color: selectedColor, isFilled: isFilled)
                                    applyStartBinding(to: &arrow, at: snapPt, snap: startSnap)
                                    arrow.rebuildPath()
                                    currentElement = arrow
                                    handledBindingPoint = true
                                    break outer
                                }
                            }
                        }
                    }
                    
                    if !handledBindingPoint, selectedTool == .select, let selectedId = selectedElementID, let el = elements.first(where: { $0.id == selectedId }) {
                        for (idx, pt) in el.bindingPoints.enumerated() {
                            if hypot(pt.x - start.x, pt.y - start.y) < 8 {
                                saveState()
                                dragMode = .editingPoint(elementId: selectedId, pointIndex: idx, original: el)
                                handledBindingPoint = true
                                break
                            }
                        }
                    }
                    
                    if !handledBindingPoint {
                        if selectedTool == .select {
                            if let hitElement = elementAt(point: start) {
                                saveState()
                                selectedElementID = hitElement.id
                                dragMode = .movingElement(hitElement.id, original: hitElement)
                                print("DEBUG: Entered .movingElement for \(hitElement.id)")
                            } else {
                                selectedElementID = nil
                                if selectionRect.contains(start) {
                                    saveState()
                                    dragMode = .movingSelection(originalRect: selectionRect, elementsSnapshot: elements)
                                    print("DEBUG: Entered .movingSelection")
                                }
                            }
                        } else {
                    if isConnectorTool, selectionRect.contains(start) {
                        selectedElementID = nil
                        dragMode = .annotating
                        let startSnap = findBinding(near: start)
                        var el = AnnotationElement(type: selectedTool, startPoint: startSnap?.point ?? start, color: selectedColor, isFilled: isFilled)
                        applyStartBinding(to: &el, at: start, snap: startSnap)
                        el.rebuildPath()
                        currentElement = el
                    } else if isDrawingTool, selectionRect.contains(start) {
                        if selectedTool == .text, let hit = elementAt(point: start), hit.type == .text {
                            saveState()
                            selectedElementID = hit.id
                            dragMode = .movingElement(hit.id, original: hit)
                        } else {
                            selectedElementID = nil
                            dragMode = .annotating
                            if selectedTool == .pencil {
                            currentElement = AnnotationElement(type: .pencil, startPoint: start, color: selectedColor, isFilled: isFilled, fillOpacity: fillOpacity)
                        } else {
                            let startSnap = findBinding(near: start)
                            var el = AnnotationElement(type: selectedTool, startPoint: startSnap?.point ?? start, color: selectedColor, isFilled: isFilled, fillOpacity: fillOpacity)
                            if let startSnap {
                                el.startBinding = startSnap.anchor
                            }
                            if selectedTool == .text {
                                el.text = "Text"
                            }
                            el.rebuildPath()
                            currentElement = el
                        }
                    }
                }
                        }
                    }
                }
            }
        case .selecting(let s):
            var current = location
            if isShiftPressed {
                let dx = current.x - s.x
                let dy = current.y - s.y
                let side = max(abs(dx), abs(dy))
                current = CGPoint(
                    x: s.x + (dx < 0 ? -side : side),
                    y: s.y + (dy < 0 ? -side : side)
                )
            }
            selectionRect = CGRect(
                x: min(s.x, current.x),
                y: min(s.y, current.y),
                width: abs(current.x - s.x),
                height: abs(current.y - s.y)
            )
        case .resizing(let handle, let orig):
            selectionRect = resizedRect(original: orig, handle: handle, translation: translation)
        case .movingSelection(let orig, let elementsSnapshot):
            selectionRect = CGRect(
                x: orig.minX + translation.width,
                y: orig.minY + translation.height,
                width: orig.width,
                height: orig.height
            )
            for (i, el) in elementsSnapshot.enumerated() {
                var moved = el
                moved.move(by: translation)
                elements[i] = moved
            }
            refreshBoundConnectors()
        case .annotating:
            if var el = currentElement {
                if el.type == .pencil {
                    el.updatePencil(currentPoint: location)
                    currentElement = el
                } else if isConnectorTool {
                    let endSnap = findBinding(near: location, excludingElementId: el.startBinding?.elementId)
                    snappedPoint = endSnap?.point
                    snappedBinding = endSnap?.anchor
                    applyEndBinding(to: &el, at: location, snap: endSnap)
                    currentElement = el
                } else {
                    let endSnap = findBinding(near: location)
                    snappedPoint = endSnap?.point
                    snappedBinding = endSnap?.anchor
                    
                    var targetPoint = endSnap?.point ?? location
                    if isShiftPressed && (el.type == .rectangle || el.type == .circle) {
                        let dx = targetPoint.x - el.startPoint.x
                        let dy = targetPoint.y - el.startPoint.y
                        let side = max(abs(dx), abs(dy))
                        targetPoint = CGPoint(
                            x: el.startPoint.x + (dx < 0 ? -side : side),
                            y: el.startPoint.y + (dy < 0 ? -side : side)
                        )
                    } else if isShiftPressed && (el.type == .line || el.type == .arrow) {
                        let dx = targetPoint.x - el.startPoint.x
                        let dy = targetPoint.y - el.startPoint.y
                        let angle = atan2(dy, dx)
                        let snappedAngle = round(angle / (.pi / 4)) * (.pi / 4)
                        let distance = hypot(dx, dy)
                        targetPoint = CGPoint(
                            x: el.startPoint.x + distance * cos(snappedAngle),
                            y: el.startPoint.y + distance * sin(snappedAngle)
                        )
                    }
                    
                    el.update(currentPoint: targetPoint)
                    currentElement = el
                }
            }
        case .movingElement(let id, let original):
            if let idx = elements.firstIndex(where: { $0.id == id }) {
                var moved = original
                moved.move(by: translation)
                elements[idx] = moved
                refreshBoundConnectors()
                print("DEBUG: Moving element \(id) by \(translation)")
            }
        case .editingPoint(let id, let index, let original):
            if let idx = elements.firstIndex(where: { $0.id == id }) {
                var el = original
                let endSnap = findBinding(near: location, excludingElementId: id)
                snappedPoint = endSnap?.point
                snappedBinding = endSnap?.anchor
                
                let newPoint = endSnap?.point ?? location
                el.updateBindingPoint(at: index, with: newPoint, anchor: endSnap?.anchor)
                elements[idx] = el
                refreshBoundConnectors()
            }
        }
    }
    
    func dragEnded(at location: CGPoint) {
        if activeTextInput != nil {
            return
        }
        
        let now = Date()
        let distance = hypot(location.x - lastClickLocation.x, location.y - lastClickLocation.y)
        let isDoubleClick = now.timeIntervalSince(lastClickTime) < 0.3 && distance < 5
        
        if isDoubleClick {
            let hit = elements.reversed().first { el in
                if el.type == .select { return false }
                if el.type == .rectangle || el.type == .circle {
                    return el.shapeRect().insetBy(dx: -30, dy: -30).contains(location)
                }
                return el.contains(point: location)
            }
            
            if let hit = hit {
                let center = CGPoint(x: hit.shapeRect().midX, y: hit.shapeRect().midY)
                if hit.type == .text {
                    activeTextInput = TextInputState(position: hit.shapeRect().midX == 0 ? center : CGPoint(x: hit.shapeRect().midX, y: hit.shapeRect().midY), text: hit.text, elementID: hit.id, bounds: hit.shapeRect(), fontSize: hit.shapeRect().height / 1.2)
                } else {
                    let sRect = hit.shapeRect()
                    let tWidth = sRect.width * 0.75
                    let tHeight = sRect.height * 0.75
                    activeTextInput = TextInputState(position: center, text: hit.text, elementID: hit.id, bounds: CGRect(x: center.x - tWidth / 2, y: center.y - tHeight / 2, width: tWidth, height: tHeight), fontSize: sRect.height / 5.33)
                }
                currentElement = nil
                lastClickTime = now
                lastClickLocation = location
                dragMode = .none
                return
            }
        }
        
        lastClickTime = now
        lastClickLocation = location
        
        switch dragMode {
        case .selecting:
            if selectionRect.width > 10 && selectionRect.height > 10 {
                isSelectingFinished = true
                selectedTool = .select
                Task { @MainActor in
                    await RecordingManager.shared.updateRegion(rect: selectionRect)
                }
            } else {
                selectionRect = .zero
                isSelectingFinished = false
            }
        case .resizing:
            Task { @MainActor in
                await RecordingManager.shared.updateRegion(rect: selectionRect)
            }
        case .movingSelection:
            Task { @MainActor in
                await RecordingManager.shared.updateRegion(rect: selectionRect)
            }
        case .annotating:
            if let element = currentElement {
                if element.type != .pencil {
                    let rect = element.shapeRect()
                    if rect.width < 5 && rect.height < 5 {
                        currentElement = nil
                        snappedPoint = nil
                        snappedBinding = nil
                        dragMode = .none
                        return
                    }
                }
                
                saveState()
                elements.append(element)
                currentElement = nil
                selectedElementID = element.id
                
                if element.type == .text {
                    // Open text edit immediately when finished drawing a text box
                    activeTextInput = TextInputState(
                        position: CGPoint(x: element.shapeRect().midX, y: element.shapeRect().midY),
                        text: element.text,
                        elementID: element.id,
                        bounds: element.shapeRect(),
                        fontSize: element.shapeRect().height / 1.2
                    )
                }
            }
            snappedPoint = nil
            snappedBinding = nil
        case .movingElement(let id, _):
            selectedElementID = id
            refreshBoundConnectors()
        case .editingPoint(let id, _, _):
            selectedElementID = id
            snappedPoint = nil
            snappedBinding = nil
            refreshBoundConnectors()
        case .none:
            if let hit = elementAt(point: location) {
                selectedElementID = hit.id
                selectedColor = hit.color
                isFilled = hit.isFilled
                fillOpacity = hit.fillOpacity
                if hit.type == .text {
                    selectedFontSize = hit.fontSize
                }
            } else if isSelectingFinished, elementAt(point: location) == nil {
                selectedElementID = nil
            }
        }
        
        dragMode = .none
    }
    
    func commitText(text: String, at location: CGPoint) {
        let el = AnnotationElement(type: .text, startPoint: location, color: self.selectedColor, text: text, isFilled: self.isFilled, fillOpacity: self.fillOpacity, fontSize: self.selectedFontSize)
        self.elements.append(el)
    }
    
    func commitActiveText() {
        guard let input = activeTextInput else { return }
        if let id = input.elementID, let idx = elements.firstIndex(where: { $0.id == id }) {
            if elements[idx].text != input.text {
                saveState()
                elements[idx].text = input.text
                if elements[idx].type == .text && input.text.isEmpty {
                    elements.remove(at: idx)
                    if selectedElementID == id {
                        selectedElementID = nil
                    }
                }
            }
        } else if !input.text.isEmpty {
            saveState()
            commitText(text: input.text, at: input.position)
        }
        activeTextInput = nil
    }

    private func resizedRect(original: CGRect, handle: Handle, translation: CGSize) -> CGRect {
        var rect = original
        switch handle {
        case .topLeft:
            rect.origin.x += translation.width
            rect.size.width -= translation.width
            rect.origin.y += translation.height
            rect.size.height -= translation.height
        case .top:
            rect.origin.y += translation.height
            rect.size.height -= translation.height
        case .topRight:
            rect.size.width += translation.width
            rect.origin.y += translation.height
            rect.size.height -= translation.height
        case .right:
            rect.size.width += translation.width
        case .bottomRight:
            rect.size.width += translation.width
            rect.size.height += translation.height
        case .bottom:
            rect.size.height += translation.height
        case .bottomLeft:
            rect.origin.x += translation.width
            rect.size.width -= translation.width
            rect.size.height += translation.height
        case .left:
            rect.origin.x += translation.width
            rect.size.width -= translation.width
        }
        return rect.standardized
    }
    
    func renderAnnotatedImage() -> CGImage? {
        let geometrySize = cachedGeometrySize
        guard geometrySize.width > 0, geometrySize.height > 0 else { return nil }
        
        let annotatedView = ZStack {
            Image(nsImage: NSImage(cgImage: cgImage, size: geometrySize))
                .resizable()
                .frame(width: geometrySize.width, height: geometrySize.height)
            
            ForEach(elements) { element in
                if element.type == .image, let nsImage = element.nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: element.shapeRect().width, height: element.shapeRect().height)
                        .position(x: element.shapeRect().midX, y: element.shapeRect().midY)
                } else if element.type == .text {
                    Text(element.text)
                        .font(.system(size: element.fontSize, weight: .bold))
                        .foregroundColor(element.color)
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 1)
                        .position(x: element.startPoint.x, y: element.startPoint.y)
                } else {
                    if element.isFilled && (element.type == .rectangle || element.type == .circle) {
                        ZStack {
                            element.path.fill(element.color.opacity(element.fillOpacity))
                            element.path.stroke(element.color, style: StrokeStyle(lineWidth: element.lineWidth, lineCap: .round, lineJoin: .round))
                        }
                    } else {
                        element.path
                            .stroke(element.color, style: StrokeStyle(lineWidth: element.lineWidth, lineCap: .round, lineJoin: .round))
                    }
                    
                    if !element.text.isEmpty {
                        Text(element.text)
                            .font(.system(size: element.fontSize, weight: .bold))
                            .foregroundColor(element.color)
                            .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 1)
                            .position(x: element.shapeRect().midX, y: element.shapeRect().midY)
                    }
                }
            }
        }
        .frame(width: geometrySize.width, height: geometrySize.height)
        
        let renderer = ImageRenderer(content: annotatedView)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return renderer.cgImage
    }
    
    func handlePosition(for handle: Handle, rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }
    
    func handleAIAnalysis() {
        guard let renderedImage = renderAnnotatedImage() else { return }
        CaptureCoordinator.shared.handleAIAnalysis(cgImage: renderedImage)
    }
    
    func toolbarPosition(for rect: CGRect, screenBounds: CGRect) -> CGPoint {
        let toolbarWidth: CGFloat = toolbarSize.width
        let toolbarHeight: CGFloat = toolbarSize.height
        let margin: CGFloat = 16
        
        let screenWidth = screenBounds.width
        let screenHeight = screenBounds.height
        
        if let customPos = customToolbarPosition {
            var x = customPos.x
            var y = customPos.y
            if x + toolbarWidth / 2 > screenWidth { x = screenWidth - toolbarWidth / 2 - margin }
            if x - toolbarWidth / 2 < 0 { x = toolbarWidth / 2 + margin }
            if y + toolbarHeight / 2 > screenHeight { y = screenHeight - toolbarHeight / 2 - margin }
            if y - toolbarHeight / 2 < 0 { y = toolbarHeight / 2 + margin }
            return CGPoint(x: x, y: y)
        }
        
        var x = rect.maxX - toolbarWidth / 2
        var y = rect.maxY + toolbarHeight / 2 + margin
        
        if x + toolbarWidth / 2 > screenWidth { x = screenWidth - toolbarWidth / 2 - margin }
        if x - toolbarWidth / 2 < 0 { x = toolbarWidth / 2 + margin }
        
        if y + toolbarHeight / 2 > screenHeight {
            y = rect.minY - toolbarHeight / 2 - margin
            if y - toolbarHeight / 2 < 0 { y = rect.maxY - toolbarHeight / 2 - margin }
        }
        
        return CGPoint(x: x, y: y)
    }
    
    func updateToolbarDrag(translation: CGSize, screenBounds: CGRect) {
        let currentPos = toolbarPosition(for: selectionRect, screenBounds: screenBounds)
        customToolbarPosition = CGPoint(x: currentPos.x + translation.width, y: currentPos.y + translation.height)
    }
    
    func toolbarHitRect(screenBounds: CGRect) -> CGRect {
        let center = toolbarPosition(for: selectionRect, screenBounds: screenBounds)
        let toolbarWidth = toolbarSize.width
        let toolbarHeight = toolbarSize.height
        return CGRect(x: center.x - toolbarWidth / 2, y: center.y - toolbarHeight / 2, width: toolbarWidth, height: toolbarHeight)
    }
    
    func handleRecordToggle() {
        guard !isProcessingRecord else { return }
        isProcessingRecord = true
        
        Task { @MainActor in
            defer { isProcessingRecord = false }
            
            if isRecording {
                do {
                    let urls = try await RecordingManager.shared.stopRecording()
                    let localUploader = LocalUploadService()
                    let finalVideoURL = try await localUploader.uploadImage(fileURL: urls.videoURL)
                    
                    print("Recording saved to: \(finalVideoURL.path)")
                    isRecording = false
                    NSWorkspace.shared.activateFileViewerSelecting([finalVideoURL])
                    handleCancel()
                    
                    // Trigger AI Documentation Generation in the background
                    Task {
                        if let ai = Phase3Workflow(), let jsonURL = urls.annotationsURL {
                            do {
                                let jsonStr = try String(contentsOf: jsonURL)
                                let trimmedJson = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)
                                let isAnnotationsEmpty = trimmedJson == "[]" || trimmedJson.isEmpty
                                
                                let docURL = finalVideoURL.deletingPathExtension().appendingPathExtension("md")
                                
                                if isAnnotationsEmpty {
                                    let placeholderDoc = """
                                    # AI Documentation Generation
                                    
                                    Không thể tự động tạo tài liệu hướng dẫn cho video ghi hình này.
                                    
                                    **Nguyên nhân:**
                                    Không có sự kiện vẽ/chú thích nào (mũi tên, hình chữ nhật, hình tròn, chữ viết...) được thực hiện trong quá trình quay, và tính năng ghi âm văn bản giọng nói chưa khả dụng.
                                    
                                    *Mẹo: Để AI tạo tài liệu hướng dẫn từng bước, vui lòng sử dụng các công cụ vẽ/chú thích trên thanh công cụ ghi hình để làm nổi bật các thao tác khi bạn đang quay video.*
                                    """
                                    try placeholderDoc.write(to: docURL, atomically: true, encoding: .utf8)
                                    print("Empty annotations. Generated placeholder documentation at: \(docURL.path)")
                                    return
                                }
                                
                                let doc = try await ai.generateStepByStepDocumentation(annotationsJSON: jsonStr, transcript: "No voice transcript available.")
                                try doc.write(to: docURL, atomically: true, encoding: .utf8)
                                print("AI Documentation saved to: \(docURL.path)")
                            } catch {
                                print("AI Generation Failed: \(error)")
                            }
                        }
                    }
                } catch {
                    isRecording = false
                    self.handleCancel() // Close overlay first!
                    
                    await MainActor.run {
                        NSApp.activate(ignoringOtherApps: true)
                        let alert = NSAlert()
                        alert.messageText = "Recording Failed"
                        alert.informativeText = "Failed to stop/save recording: \(error.localizedDescription)"
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
                }
            } else {
                do {
                    let screen = parentWindow?.screen ?? NSScreen.main
                    let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
                    try await RecordingManager.shared.startRecording(region: selectionRect, displayID: displayID, excludingWindowIDs: [])
                    isRecording = true
                } catch {
                    self.handleCancel() // Close overlay first!
                    
                    await MainActor.run {
                        NSApp.activate(ignoringOtherApps: true)
                        let alert = NSAlert()
                        alert.messageText = "Recording Failed"
                        alert.informativeText = "Failed to start recording: \(error.localizedDescription)"
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
                }
            }
        }
    }
}
