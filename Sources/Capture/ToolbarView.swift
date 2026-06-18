import SwiftUI
import Foundation
import AppKit

struct ToolbarView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @Binding var showColorPicker: Bool
    let screenBounds: CGRect
    
    @State private var isHovered = false
    @State private var isColorHovered = false
    
    var body: some View {
        ZStack {

            Group {
                if viewModel.isToolbarCollapsed {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.isToolbarCollapsed = false
                        }
                    }) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 8) {
                        HoverableDragBar(viewModel: viewModel)
                        
                        HStack(spacing: 6) {
                            Group {
                                ToolButton(icon: "hand.point.up.left", isSelected: viewModel.selectedTool == .select) { viewModel.selectTool(.select) }
                                ToolButton(icon: "pencil.tip", isSelected: viewModel.selectedTool == .pencil) { viewModel.selectTool(.pencil) }
                                ToolButton(icon: "square", isSelected: viewModel.selectedTool == .rectangle) { viewModel.selectTool(.rectangle) }
                                ToolButton(icon: "circle", isSelected: viewModel.selectedTool == .circle) { viewModel.selectTool(.circle) }
                                ToolButton(icon: "arrow.up.right", isSelected: viewModel.selectedTool == .arrow) { viewModel.selectTool(.arrow) }
                                ToolButton(icon: "line.diagonal", isSelected: viewModel.selectedTool == .line) { viewModel.selectTool(.line) }
                                ToolButton(icon: "textformat", isSelected: viewModel.selectedTool == .text) { viewModel.selectTool(.text) }
                                ToolButton(icon: "photo", isSelected: false) { viewModel.openImage() }
                            }
                            
                            Divider().frame(width: 1, height: 16).opacity(0.3)
                            
                            HStack(spacing: 6) {
                                ToolButton(icon: viewModel.isFilled ? "square.fill" : "square.dashed", isSelected: viewModel.isFilled) {
                                    viewModel.isFilled.toggle()
                                }
                                
                                if viewModel.isFilled && (viewModel.selectedTool == .rectangle || viewModel.selectedTool == .circle || viewModel.selectedTool == .select) {
                                    Slider(value: $viewModel.fillOpacity, in: 0.1...1.0)
                                        .frame(width: 50)
                                        .tint(viewModel.selectedColor)
                                        .controlSize(.mini)
                                }
                            }
                            
                            Divider().frame(width: 1, height: 16).opacity(0.3)
                            
                            // Color picker using popover
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showColorPicker.toggle()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(viewModel.selectedColor)
                                        .frame(width: 14, height: 14)
                                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 6)
                                .frame(height: 24)
                                .background(isColorHovered ? Color.white.opacity(0.15) : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { hover in
                                isColorHovered = hover
                            }
                            .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                                ColorPickerPopoverView(viewModel: viewModel, isPresented: $showColorPicker)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isToolbarCollapsed)
                } // ends else
            } // ends Group
        } // ends ZStack
        .fixedSize()
        .animation(.default, value: viewModel.isToolbarCollapsed)
        .animation(.default, value: showColorPicker)
        .animation(.default, value: viewModel.isFilled)
    }
}

struct HoverableDragBar: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var isHovered = false
    @State private var isCloseHovered = false
    @State private var isCollapseHovered = false
    @State private var isLockHovered = false
    @State private var isHelpHovered = false
    @State private var showAIOptions = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Close, Lock, Help and Undo/Redo buttons on the left
            HStack(spacing: 8) {
                // Close Button (macOS Traffic Light style - red)
                Button(action: {
                    viewModel.handleCancel()
                }) {
                    Circle()
                        .fill(Color(red: 0.95, green: 0.36, blue: 0.34))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.black.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hover in
                    isCloseHovered = hover
                }
                
                // Collapse Button (macOS Traffic Light style - yellow)
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.isToolbarCollapsed = true
                    }
                }) {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.74, blue: 0.18))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "minus")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.black.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hover in
                    isCollapseHovered = hover
                }
                .help(Text("Collapse toolbar"))
                
                // Lock Button (macOS Traffic Light style - green)
                Button(action: {
                    viewModel.isInteractMode.toggle()
                }) {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.77, blue: 0.28))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: viewModel.isInteractMode ? "lock.fill" : "lock.open.fill")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.black.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hover in
                    isLockHovered = hover
                }
                .help(Text("Toggle interaction mode (lock/unlock)"))
                
                // Help Button (macOS style blue circle)
                Button(action: {
                    viewModel.showHelpPopover.toggle()
                }) {
                    Circle()
                        .fill(Color(red: 0.22, green: 0.50, blue: 0.96))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "questionmark")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hover in
                    isHelpHovered = hover
                }
                .popover(isPresented: $viewModel.showHelpPopover, arrowEdge: .top) {
                    ShortcutsHelpView()
                }
                
                Divider().frame(height: 12).padding(.horizontal, 2)
                
                // Undo Button
                ActionToolButton(icon: "arrow.uturn.backward", color: .white, size: 10) {
                    viewModel.undo()
                }
                .disabled(!viewModel.canUndo)
                .opacity(viewModel.canUndo ? 1.0 : 0.4)
                
                // Redo Button
                ActionToolButton(icon: "arrow.uturn.forward", color: .white, size: 10) {
                    viewModel.redo()
                }
                .disabled(!viewModel.canRedo)
                .opacity(viewModel.canRedo ? 1.0 : 0.4)
            }
            .padding(.leading, 12)
            
            // Draggable Middle
            ZStack {
                WindowDragOverlay()
                
                Capsule()
                    .fill(isHovered ? Color.white.opacity(0.4) : Color.white.opacity(0.15))
                    .frame(width: 36, height: 4)
                    .offset(y: 1)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            
            // Functional Buttons on the right (Pause/Play, Record, Upload, AI, Save)
            HStack(spacing: 8) {
                if viewModel.isRecording {
                    ActionToolButton(icon: viewModel.isPaused ? "play.fill" : "pause.fill", color: .white, size: 10) {
                        if viewModel.isPaused {
                            RecordingManager.shared.resumeRecording()
                            viewModel.isPaused = false
                        } else {
                            RecordingManager.shared.pauseRecording()
                            viewModel.isPaused = true
                        }
                    }
                }
                
                if viewModel.isProcessingRecord {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                } else {
                    ActionToolButton(icon: viewModel.isRecording ? "stop.circle.fill" : "record.circle", color: viewModel.isRecording ? .red : .white, size: 11) {
                        viewModel.handleRecordToggle()
                    }
                }
                
                Divider().frame(height: 12).padding(.horizontal, 2)
                
                ActionToolButton(icon: "icloud.and.arrow.up.fill", color: .blue, size: 10) {
                    viewModel.handleUpload()
                }
                
                ActionToolButton(icon: "sparkles", color: .purple, size: 10) {
                    showAIOptions.toggle()
                }
                .popover(isPresented: $showAIOptions, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        MenuItemButton(title: "Explain Image", icon: "sparkles") {
                            viewModel.handleAIAnalysis(actionType: .explain)
                            showAIOptions = false
                        }
                        
                        MenuItemButton(title: "Translate Text", icon: "character.book.closed") {
                            viewModel.handleAIAnalysis(actionType: .translate)
                            showAIOptions = false
                        }
                        
                        MenuItemButton(title: "Refactor Code", icon: "chevron.left.forwardslash.chevron.right") {
                            viewModel.handleAIAnalysis(actionType: .refactor)
                            showAIOptions = false
                        }
                    }
                    .padding(6)
                    .frame(width: 140)
                    .padding(8)
                    .background(Color(NSColor.windowBackgroundColor))
                }
                
                ActionToolButton(icon: "checkmark", color: .green, size: 10) {
                    viewModel.handleComplete()
                }
            }
            .padding(.trailing, 12)
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        .padding(.horizontal, -12)
        .padding(.top, -10)
        .padding(.bottom, -4)
        .onHover { hover in
            isHovered = hover
        }
    }
}

struct ActionToolButton: View {
    let icon: String
    let color: Color
    var size: CGFloat = 11
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundColor(color)
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

struct ShortcutsHelpView: View {
    let shortcuts: [(key: String, desc: LocalizedStringKey)] = [
        ("V", "Select / Move elements"),
        ("B", "Pencil tool (Freehand drawing)"),
        ("M", "Rectangle shape"),
        ("C", "Circle shape"),
        ("A", "Arrow indicator"),
        ("L", "Straight line"),
        ("T", "Text label"),
        ("O", "Import external image"),
        ("F", "Toggle shape background fill"),
        ("I", "Toggle interaction mode (lock/unlock)"),
        ("R / ⌘R", "Start / Stop screen recording"),
        ("P / ⌘P", "Pause / Resume screen recording"),
        ("⌘Z", "Undo last drawing action"),
        ("⌘⇧Z", "Redo last undone action"),
        ("⌘C", "Copy screenshot to Clipboard"),
        ("⌘S / Enter", "Complete & Save screenshot locally"),
        ("⌘U", "Complete & Upload screenshot to cloud"),
        ("⌘I", "Trigger AI vision analysis"),
        ("ESC", "Cancel and close capture"),
        ("H", "Toggle this shortcut list")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "keyboard")
                    .foregroundColor(.blue)
                Text("Keyboard Shortcuts")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .padding(.bottom, 4)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(0..<shortcuts.count, id: \.self) { index in
                        let item = shortcuts[index]
                        HStack(alignment: .center) {
                            Text(item.key)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(5)
                                .foregroundColor(.blue)
                            
                            Spacer(minLength: 12)
                            
                            Text(item.desc)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
            
            Divider()
            
            HStack {
                Spacer()
                Button(action: {
                    if let url = URL(string: "https://notex.work") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                        Text("Visit Website")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .focusable(false)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 330)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }
}

struct PresetColorCell: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 20, height: 20)
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: isSelected ? 2.0 : (isHovered ? 1.0 : 0))
            )
            .scaleEffect(isHovered ? 1.15 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onTapGesture(perform: action)
            .onHover { hover in
                isHovered = hover
            }
    }
}

struct ColorPickerPopoverView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Select Color")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Grid of presets
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 4), spacing: 8) {
                ForEach(viewModel.colors, id: \.self) { color in
                    PresetColorCell(color: color, isSelected: viewModel.selectedColor == color) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.selectedColor = color
                            isPresented = false
                        }
                    }
                }
            }
            
            Divider()
            
            // Custom Color Button
            Button(action: {
                isPresented = false
                NSColorPanel.shared.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
                NSColorPanel.shared.color = NSColor(viewModel.selectedColor)
                NSColorPanel.shared.orderFront(nil)
                
                // Set up observer
                ColorPanelHelper.shared.onColorChange = { newColor in
                    viewModel.selectedColor = newColor
                }
                ColorPanelHelper.shared.startObserving()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette")
                      Text("Custom Color...")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(12)
        .frame(width: 140)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
class ColorPanelHelper: NSObject {
    static let shared = ColorPanelHelper()
    var onColorChange: ((Color) -> Void)?
    private var isObserving = false
    
    private override init() {
        super.init()
    }
    
    func startObserving() {
        guard !isObserving else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(colorChanged(_:)), name: NSColorPanel.colorDidChangeNotification, object: nil)
        isObserving = true
    }
    
    @objc private func colorChanged(_ notification: Notification) {
        if let panel = notification.object as? NSColorPanel {
            let nsColor = panel.color
            let color = Color(nsColor)
            onColorChange?(color)
        }
    }
}

struct MenuItemButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? .white : .primary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .background(isHovered ? Color.accentColor : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            action()
        }
    }
}