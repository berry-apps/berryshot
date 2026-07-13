import SwiftUI
import CoreGraphics

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var showColorPicker = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if viewModel.isInteractMode || viewModel.isRecording {
                    Image(nsImage: NSImage(cgImage: viewModel.cgImage, size: geometry.size))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .mask(
                            CutoutShape(rect: viewModel.selectionRect.width > 0 && viewModel.selectionRect.height > 0 ? viewModel.selectionRect : .zero)
                                .fill(style: FillStyle(eoFill: true))
                        )
                        
                    Color.black.opacity(0.4)
                        .mask(
                            CutoutShape(rect: viewModel.selectionRect.width > 0 && viewModel.selectionRect.height > 0 ? viewModel.selectionRect : .zero)
                                .fill(style: FillStyle(eoFill: true))
                        )
                } else {
                    Image(nsImage: NSImage(cgImage: viewModel.cgImage, size: geometry.size))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        
                    Color.black.opacity(0.4)
                        .mask(
                            CutoutShape(rect: viewModel.selectionRect.width > 0 && viewModel.selectionRect.height > 0 ? viewModel.selectionRect : .zero)
                                .fill(style: FillStyle(eoFill: true))
                        )
                }
                
                if viewModel.selectionRect.width > 0 && viewModel.selectionRect.height > 0 {
                    Rectangle()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                        .frame(width: viewModel.selectionRect.width, height: viewModel.selectionRect.height)
                        .position(x: viewModel.selectionRect.midX, y: viewModel.selectionRect.midY)
                    
                    if viewModel.isSelectingFinished {
                        ForEach(Handle.allCases, id: \.self) { handle in
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                                .position(viewModel.handlePosition(for: handle, rect: viewModel.selectionRect))
                        }
                    }
                    
                    ForEach(viewModel.elements) { element in
                        if element.type == .image, let nsImage = element.nsImage {
                            ZStack {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .frame(width: element.shapeRect().width, height: element.shapeRect().height)
                                
                                if !element.text.isEmpty && viewModel.activeTextInput?.elementID != element.id {
                                    let tWidth = element.shapeRect().width * 0.75
                                    let tHeight = element.shapeRect().height * 0.75
                                    Text(element.text)
                                        .font(.system(size: min(tHeight / 4, 24), weight: .bold))
                                        .foregroundColor(element.color)
                                        .shadow(color: .black.opacity(0.7), radius: 2, x: 1, y: 1)
                                        .frame(width: tWidth, height: tHeight)
                                        .minimumScaleFactor(0.1)
                                }
                            }
                            .frame(width: element.shapeRect().width, height: element.shapeRect().height)
                            .position(x: element.shapeRect().midX, y: element.shapeRect().midY)
                        } else if element.type == .text {
                            if viewModel.activeTextInput?.elementID != element.id {
                                Text(element.text)
                                    .font(.system(size: element.shapeRect().height / 1.2, weight: .bold))
                                    .foregroundColor(element.color)
                                    .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 1)
                                    .frame(width: element.shapeRect().width, height: element.shapeRect().height)
                                    .minimumScaleFactor(0.1)
                                    .position(x: element.shapeRect().midX, y: element.shapeRect().midY)
                            }
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
                            
                            if !element.text.isEmpty && viewModel.activeTextInput?.elementID != element.id {
                                let tWidth = element.shapeRect().width * 0.75
                                let tHeight = element.shapeRect().height * 0.75
                                Text(element.text)
                                    .font(.system(size: tHeight / 4, weight: .bold))
                                    .foregroundColor(element.color)
                                    .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 1)
                                    .frame(width: tWidth, height: tHeight)
                                    .minimumScaleFactor(0.1)
                                    .position(x: element.shapeRect().midX, y: element.shapeRect().midY)
                            }
                        }
                        
                        if viewModel.selectedElementIDs.contains(element.id) {
                                if element.type == .line || element.type == .arrow || element.type == .curvedLine || element.type == .curvedArrow {
                                    element.path
                                        .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: element.lineWidth + 6, dash: []))
                                } else {
                                    Rectangle()
                                        .stroke(Color.blue.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                                        .frame(width: element.boundingRect.width + 8, height: element.boundingRect.height + 8)
                                        .position(x: element.boundingRect.midX, y: element.boundingRect.midY)
                                }
                            
                            HStack(spacing: 8) {
                                ContextMenuButton(icon: "square.3.layers.3d.bottom.filled", size: 11, color: .white) {
                                    viewModel.sendToBack(elementId: element.id)
                                }
                                
                                ContextMenuButton(icon: "square.3.layers.3d.top.filled", size: 11, color: .white) {
                                    viewModel.bringToFront(elementId: element.id)
                                }
                                
                                ContextMenuButton(icon: "xmark.circle.fill", size: 12, color: .red, isPalette: true) {
                                    viewModel.deleteSelectedElement()
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .position(x: element.boundingRect.maxX + 35, y: element.boundingRect.minY - 20)
                        }
                    }
                    
                    if let current = viewModel.currentElement {
                        if current.type == .image, let nsImage = current.nsImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .frame(width: current.shapeRect().width, height: current.shapeRect().height)
                                .position(x: current.shapeRect().midX, y: current.shapeRect().midY)
                        } else if current.isFilled && (current.type == .rectangle || current.type == .circle) {
                            ZStack {
                                current.path.fill(current.color.opacity(current.fillOpacity))
                                current.path.stroke(current.color, style: StrokeStyle(lineWidth: current.lineWidth, lineCap: .round, lineJoin: .round))
                            }
                        } else {
                            current.path
                                .stroke(current.color, style: StrokeStyle(lineWidth: current.lineWidth, lineCap: .round, lineJoin: .round))
                        }
                    }
                    
                    if let textInput = viewModel.activeTextInput {
                        TextField("Nhập text...", text: Binding(
                            get: { viewModel.activeTextInput?.text ?? "" },
                            set: { viewModel.activeTextInput?.text = $0 }
                        ))
                        .accessibilityLabel("Text Input")
                        .accessibilityAddTraits(.isKeyboardKey)
                        .multilineTextAlignment(.center)
                        .focused($isTextFieldFocused)
                        .font(.system(size: textInput.fontSize, weight: .bold))
                        .foregroundColor(viewModel.selectedColor)
                        .textFieldStyle(.plain)
                        .minimumScaleFactor(0.1)
                        .frame(width: textInput.bounds.width, height: textInput.bounds.height)
                        .position(x: textInput.bounds.midX, y: textInput.bounds.midY)
                        .onSubmit {
                            viewModel.commitActiveText()
                        }
                        .onAppear {
                            isTextFieldFocused = true
                        }
                    }
                    
                    // Binding points kiểu Excalidraw
                    ForEach(Array(viewModel.bindingPointItems().enumerated()), id: \.offset) { _, item in
                        let isHovered = viewModel.snappedBinding == BindingAnchor(elementId: item.elementId, pointIndex: item.index)
                        BindingPointView(isActive: isHovered, isSelected: viewModel.selectedElementIDs.contains(item.elementId), isConnector: item.isConnector)
                            .position(x: item.point.x, y: item.point.y)
                    }
                    
                    // Snap indicator khi đang kéo line/arrow
                    if let sp = viewModel.snappedPoint, viewModel.isConnectorTool || viewModel.isDrawingTool, viewModel.isSelectingFinished {
                        BindingPointView(isActive: true, isSelected: true, isConnector: true)
                            .position(x: sp.x, y: sp.y)
                    }
                }

            }
            .contentShape(Rectangle())
            .onAppear {
                viewModel.cachedGeometrySize = geometry.size
                // Start with no pre-set region (Lightshot-style): user drags to draw the capture area.
                // viewModel.selectDefaultRegion()
                viewModel.setupEventMonitor()
            }
            .onDisappear {
                viewModel.removeEventMonitor()
            }
            .onChange(of: geometry.size) { _, newSize in
                viewModel.cachedGeometrySize = newSize
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    viewModel.updateHover(at: location)
                case .ended:
                    viewModel.endHover()
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Chấm binding kiểu Excalidraw — viền trắng, lõi xanh, phóng to khi active
struct BindingPointView: View {
    let isActive: Bool
    let isSelected: Bool
    let isConnector: Bool
    let size: CGFloat = 8
    
    var body: some View {
        ZStack {
            if isConnector {
                Circle()
                    .fill(Color.white)
                    .frame(width: size + 4, height: size + 4)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                Circle()
                    .fill(isActive ? Color.blue : Color.blue.opacity(0.8))
                    .frame(width: size, height: size)
                Image(systemName: "plus")
                    .font(.system(size: size - 2, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: size + 2, height: size + 2)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                Rectangle()
                    .fill(isActive ? Color.blue : Color.white)
                    .stroke(Color.blue.opacity(0.8), lineWidth: 1.5)
                    .frame(width: size, height: size)
            }
        }
    }
}

struct ToolButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : (isHovered ? .white : .white.opacity(0.7)))
                .frame(width: 24, height: 24)
                .background(isSelected ? Color.blue : (isHovered ? Color.white.opacity(0.15) : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovered = hover
        }
    }
}

struct ContextMenuButton: View {
    let icon: String
    let size: CGFloat
    let color: Color
    var isPalette: Bool = false
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Group {
                if isPalette {
                    Image(systemName: icon)
                        .font(.system(size: size))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, color)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: size))
                        .foregroundColor(color)
                }
            }
            .frame(width: 20, height: 20)
            .background(isHovered ? Color.white.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovered = hover
        }
    }
}

struct CutoutShape: Shape {
    let rect: CGRect
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(self.rect)
        return path
    }
}
