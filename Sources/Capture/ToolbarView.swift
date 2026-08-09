import SwiftUI
import Foundation
import AppKit

/// A row of controls laid out horizontally when the toolbar is docked
/// top/bottom, or as a column when docked left/right — swapping `HStack`
/// for `VStack` per docking side, since `AnyLayout` lets both conform to
/// the same `Layout` protocol without restructuring the children.
private func adaptiveLayout(isVertical: Bool, spacing: CGFloat) -> AnyLayout {
    isVertical ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
}

/// A thin separator between adjacent controls in an `adaptiveLayout` row —
/// a vertical line between horizontally-arranged controls, or a horizontal
/// line between vertically-stacked ones.
private struct AdaptiveDivider: View {
    let isVertical: Bool
    var body: some View {
        Divider()
            .frame(width: isVertical ? 16 : 1, height: isVertical ? 1 : 16)
            .opacity(0.3)
    }
}

struct ToolbarView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @Binding var showColorPicker: Bool
    let screenBounds: CGRect

    @State private var isHovered = false
    @State private var isColorHovered = false

    private func redactionIcon(for style: RedactionStyle?) -> String {
        switch style {
        case .blur: return "aqi.medium"
        case .pixelate: return "square.grid.3x3.fill"
        case .solid: return "rectangle.fill"
        case nil: return "eye.slash"
        }
    }
    
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
                    .help(Text("Expand Toolbar"))
                } else {
                    let isVertical = viewModel.isToolbarVertical
                    // Top/bottom docking stacks 2 ROWS (drag bar row, then
                    // tool row) with each row flowing horizontally. Rotated
                    // 90° for left/right docking, that becomes 2 COLUMNS
                    // (drag bar column, then tool column) side by side, each
                    // flowing vertically — so this outer container's axis is
                    // the OPPOSITE of the inner rows', not the same. Stacking
                    // two already-vertical columns on top of each other
                    // (same axis both levels) would just make one extremely
                    // tall single-file column that overflows/overlaps the
                    // selection instead of forming a compact 2-column block.
                    // .top instead of HStack's default .center — otherwise the
                    // drag-bar column and tool column (usually different
                    // heights) sit vertically centered against each other
                    // instead of both starting flush at the same top edge.
                    let outerLayout: AnyLayout = isVertical
                        ? AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                        : AnyLayout(VStackLayout(spacing: 8))
                    let toolRowLayout = adaptiveLayout(isVertical: isVertical, spacing: 6)
                    let fillGroupLayout = adaptiveLayout(isVertical: isVertical, spacing: 6)
                    outerLayout {
                        HoverableDragBar(viewModel: viewModel)

                        toolRowLayout {
                            Group {
                                ToolButton(icon: "hand.point.up.left", isSelected: viewModel.selectedTool == .select) { viewModel.selectTool(.select) }
                                    .help("Select & Move (V)")
                                ToolButton(icon: "pencil.tip", isSelected: viewModel.selectedTool == .pencil) { viewModel.selectTool(.pencil) }
                                    .help("Pencil — Freehand Drawing (B)")
                                ToolButton(icon: "square", isSelected: viewModel.selectedTool == .rectangle) { viewModel.selectTool(.rectangle) }
                                    .help("Rectangle (M)")
                                ToolButton(icon: "circle", isSelected: viewModel.selectedTool == .circle) { viewModel.selectTool(.circle) }
                                    .help("Circle / Oval (C)")
                                DropdownToolButton(
                                    mainIcon: viewModel.selectedTool == .curvedArrow ? "arrow.turn.up.right" : "arrow.up.right",
                                    isSelected: viewModel.selectedTool == .arrow || viewModel.selectedTool == .curvedArrow,
                                    mainAction: { viewModel.selectTool(viewModel.selectedTool == .curvedArrow ? .curvedArrow : .arrow) },
                                    menuItems: [
                                        ("Straight Arrow", "arrow.up.right", { viewModel.selectTool(.arrow) }),
                                        ("Curved Arrow", "arrow.turn.up.right", { viewModel.selectTool(.curvedArrow) })
                                    ],
                                    isVertical: isVertical
                                )
                                .help("Arrow — Straight or Curved (A)")
                                DropdownToolButton(
                                    mainIcon: viewModel.selectedTool == .curvedLine ? "waveform.path" : "line.diagonal",
                                    isSelected: viewModel.selectedTool == .line || viewModel.selectedTool == .curvedLine,
                                    mainAction: { viewModel.selectTool(viewModel.selectedTool == .curvedLine ? .curvedLine : .line) },
                                    menuItems: [
                                        ("Straight Line", "line.diagonal", { viewModel.selectTool(.line) }),
                                        ("Curved Connector", "waveform.path", { viewModel.selectTool(.curvedLine) })
                                    ],
                                    isVertical: isVertical
                                )
                                .help("Line — Straight or Curved (L)")
                                ToolButton(icon: "textformat", isSelected: viewModel.selectedTool == .text) { viewModel.selectTool(.text) }
                                    .help("Text Label (T)")
                                DropdownToolButton(
                                    // Reflects whichever style (blur/pixelate/solid) is
                                    // actually active, matching how the Arrow/Line
                                    // dropdowns already show their active sub-tool's icon
                                    // instead of one static icon regardless of selection.
                                    mainIcon: redactionIcon(for: viewModel.activeRedactionStyle),
                                    isSelected: viewModel.activeRedactionStyle != nil,
                                    mainAction: {
                                        viewModel.selectRedactionTool(style: viewModel.activeRedactionStyle ?? RedactionSettings.shared.style)
                                    },
                                    menuItems: [
                                        ("Blur", redactionIcon(for: .blur), { viewModel.selectRedactionTool(style: .blur) }),
                                        ("Pixelate", redactionIcon(for: .pixelate), { viewModel.selectRedactionTool(style: .pixelate) }),
                                        ("Solid Cover", redactionIcon(for: .solid), { viewModel.selectRedactionTool(style: .solid) })
                                    ],
                                    isVertical: isVertical
                                )
                                .help("Mark a region to redact — BerryShot flattens it (blur, pixelate, or solid cover) before the capture is saved or uploaded")
                                ToolButton(icon: "photo", isSelected: false) { viewModel.openImage() }
                                    .help("Import Image (O)")

                                AdaptiveDivider(isVertical: isVertical)

                                ToolButton(icon: "scroll", isSelected: false) {
                                    CaptureCoordinator.shared.startScrollCapture()
                                }
                                .help("Scroll Capture — capture full scrollable content")
                            }

                            AdaptiveDivider(isVertical: isVertical)

                            ToolButton(icon: "plus.magnifyingglass", isSelected: viewModel.isUpscaleEnabled) {
                                viewModel.isUpscaleEnabled.toggle()
                            }
                            .help("Pixel-Perfect Upscale 2x (Nearest Neighbor)")

                            AdaptiveDivider(isVertical: isVertical)

                            fillGroupLayout {
                                ToolButton(icon: viewModel.isFilled ? "square.fill" : "square.dashed", isSelected: viewModel.isFilled) {
                                    viewModel.isFilled.toggle()
                                }
                                .help(Text(viewModel.isFilled ? "Fill: On — Toggle Shape Background Fill (F)" : "Fill: Off — Toggle Shape Background Fill (F)"))

                                if viewModel.isFilled && (viewModel.selectedTool == .rectangle || viewModel.selectedTool == .circle || viewModel.selectedTool == .select) {
                                    // A plain Slider has no built-in vertical orientation on
                                    // macOS — rotate it, then re-frame to the ROTATED bounding
                                    // box (its own height becomes the column's width) so it
                                    // occupies a narrow column slot instead of forcing the
                                    // whole vertical toolbar wide.
                                    Slider(value: $viewModel.fillOpacity, in: 0.1...1.0)
                                        .frame(width: 50)
                                        .rotationEffect(.degrees(isVertical ? -90 : 0))
                                        .frame(width: isVertical ? 16 : 50, height: isVertical ? 50 : nil)
                                        .tint(viewModel.selectedColor)
                                        .controlSize(.mini)
                                }
                            }

                            AdaptiveDivider(isVertical: isVertical)

                            // Color picker using popover
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showColorPicker.toggle()
                                }
                            }) {
                                let swatchLayout = adaptiveLayout(isVertical: isVertical, spacing: 4)
                                swatchLayout {
                                    Circle()
                                        .fill(viewModel.selectedColor)
                                        .frame(width: 14, height: 14)
                                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(isVertical ? .vertical : .horizontal, 6)
                                .frame(width: isVertical ? 24 : nil, height: isVertical ? nil : 24)
                                .background(isColorHovered ? Color.white.opacity(0.15) : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Stroke / Fill Color")
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

struct DropdownToolButton: View {
    let mainIcon: String
    let isSelected: Bool
    let mainAction: () -> Void
    let menuItems: [(String, String, () -> Void)]
    var isVertical: Bool = false
    @State private var isHovered = false

    var body: some View {
        let layout = adaptiveLayout(isVertical: isVertical, spacing: 0)
        layout {
            Button(action: mainAction) {
                Image(systemName: mainIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : (isHovered ? .white : .white.opacity(0.7)))
                    .frame(width: isVertical ? 24 : 26, height: isVertical ? 20 : 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                .frame(width: isVertical ? 16 : 1, height: isVertical ? 1 : 24)
                .padding(isVertical ? .vertical : .horizontal, 2)

            Menu {
                ForEach(menuItems, id: \.0) { item in
                    Button(action: item.2) {
                        Label(item.0, systemImage: item.1)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isSelected ? .white : (isHovered ? .white : .white.opacity(0.7)))
                    .frame(width: 24, height: isVertical ? 16 : 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .background(isSelected ? Color.blue : (isHovered ? Color.white.opacity(0.15) : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hover in
            isHovered = hover
        }
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
        let isVertical = viewModel.isToolbarVertical
        let outerLayout = adaptiveLayout(isVertical: isVertical, spacing: 0)
        let leftGroupLayout = adaptiveLayout(isVertical: isVertical, spacing: 8)
        let rightGroupLayout = adaptiveLayout(isVertical: isVertical, spacing: 8)
        outerLayout {
            // Close, Lock, Help and Undo/Redo buttons on the leading edge
            leftGroupLayout {
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
                .help(Text("Cancel Capture (Esc)"))

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
                .help(Text("Show Keyboard Shortcuts (H)"))
                .onHover { hover in
                    isHelpHovered = hover
                }
                .popover(isPresented: $viewModel.showHelpPopover, arrowEdge: .top) {
                    ShortcutsHelpView()
                }

                Divider()
                    .frame(width: isVertical ? 12 : 1, height: isVertical ? 1 : 12)
                    .padding(isVertical ? .vertical : .horizontal, 2)

                // Undo Button
                ActionToolButton(icon: "arrow.uturn.backward", color: .white, size: 10) {
                    viewModel.undo()
                }
                .disabled(!viewModel.canUndo)
                .opacity(viewModel.canUndo ? 1.0 : 0.4)
                .help(Text("Undo (⌘Z)"))

                // Redo Button
                ActionToolButton(icon: "arrow.uturn.forward", color: .white, size: 10) {
                    viewModel.redo()
                }
                .disabled(!viewModel.canRedo)
                .opacity(viewModel.canRedo ? 1.0 : 0.4)
                .help(Text("Redo (⌘⇧Z)"))

                // Clear All Button — "eraser" reads as clearing the canvas;
                // "trash" reads as permanently deleting something, which
                // this isn't (it's one normal, undoable ⌘Z step).
                ActionToolButton(icon: "eraser.fill", color: .white, size: 10) {
                    viewModel.clearAllElements()
                }
                .disabled(viewModel.elements.isEmpty)
                .opacity(viewModel.elements.isEmpty ? 0.4 : 1.0)
                .help("Clear all drawn shapes")

                // Select Full Screen — moved here from the main tool row.
                ActionToolButton(icon: "macwindow", color: .white, size: 10) {
                    viewModel.selectFullScreen()
                }
                .help("Select Full Screen")

                // Visible review badge (04-sensitive-redaction-spec.md section 6):
                // shows how many regions are currently marked for redaction
                // before the capture is confirmed.
                if viewModel.manualRedactionRegionCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash.fill")
                        Text("\(viewModel.manualRedactionRegionCount)")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.pink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.pink.opacity(0.18))
                    .clipShape(Capsule())
                    .help("\(viewModel.manualRedactionRegionCount) region(s) will be redacted before this capture is saved or uploaded")
                }
            }
            .padding(isVertical ? .top : .leading, 12)

            // Draggable Middle
            ZStack {
                WindowDragOverlay()

                Capsule()
                    .fill(isHovered ? Color.white.opacity(0.4) : Color.white.opacity(0.15))
                    .frame(width: isVertical ? 4 : 36, height: isVertical ? 36 : 4)
                    .offset(x: isVertical ? 1 : 0, y: isVertical ? 0 : 1)
                    .allowsHitTesting(false)
            }
            // Only stretch along the axis this bar actually flows on — this
            // sits between leftGroup and rightGroup as a column (VStack)
            // when vertical, so it should only claim extra HEIGHT there;
            // still claiming maxWidth: .infinity too made it bleed sideways
            // into the neighboring tool column when the two now sit side by
            // side, covering its icons.
            .frame(maxWidth: isVertical ? nil : .infinity, maxHeight: isVertical ? .infinity : nil)
            .contentShape(Rectangle())

            // Functional Buttons on the trailing edge (Pause/Play, Record, Upload, AI, Save)
            rightGroupLayout {
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
                    .help(Text(viewModel.isPaused ? "Resume Recording" : "Pause Recording"))

                    ActionToolButton(
                        icon: viewModel.isMicMuted ? "mic.slash.fill" : "mic.fill",
                        color: viewModel.isMicMuted ? .red : .white,
                        size: 10
                    ) {
                        viewModel.toggleMicMute()
                    }
                    .help(Text(viewModel.isMicMuted ? "Unmute Microphone" : "Mute Microphone"))

                    ActionToolButton(
                        icon: "doc.text.fill",
                        color: viewModel.showLiveNotes ? .green : .white,
                        size: 10
                    ) {
                        viewModel.toggleLiveNotes()
                    }
                    .help(Text("Live Meeting Notes"))
                }

                if viewModel.isProcessingRecord {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                } else {
                    ActionToolButton(icon: viewModel.isRecording ? "stop.circle.fill" : "record.circle", color: viewModel.isRecording ? .red : .white, size: 11) {
                        viewModel.handleRecordToggle()
                    }
                    .help(Text(viewModel.isRecording ? "Stop Recording" : "Start Recording"))
                }

                Divider()
                    .frame(width: isVertical ? 12 : 1, height: isVertical ? 1 : 12)
                    .padding(isVertical ? .vertical : .horizontal, 2)

                ActionToolButton(icon: "icloud.and.arrow.up.fill", color: .blue, size: 10) {
                    viewModel.handleUpload()
                }
                .help(Text("Upload to Cloud (⌘U)"))

                ActionToolButton(icon: "sparkles", color: .purple, size: 10) {
                    viewModel.handleAIAnalysis(actionType: .explain) // The actionType won't matter as much once we use the Chat UI
                }
                .help(Text("AI Vision Analysis (⌘I)"))

                ActionToolButton(icon: "checkmark", color: .green, size: 10) {
                    viewModel.handleComplete()
                }
                .help(Text("Complete & Save (Enter)"))
            }
            .padding(isVertical ? .bottom : .trailing, 12)
        }
        // 28pt was always this bar's CROSS-axis thickness, and
        // maxWidth: .infinity let it fill the main axis — both fixed to
        // literal width/height regardless of orientation, so in vertical
        // mode this crushed an entire column of stacked icons down to
        // 28pt tall, overlapping them. Swap which dimension is fixed vs.
        // expanding to match whichever axis this bar is actually flowing on.
        .frame(width: isVertical ? 28 : nil, height: isVertical ? nil : 28)
        .frame(maxWidth: isVertical ? nil : .infinity, maxHeight: isVertical ? .infinity : nil)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        // This negative padding expands the bar outward to visually blend
        // with the tool row it sits above in horizontal mode. Applied
        // unconditionally it would also expand sideways in vertical mode,
        // where the tool column sits beside (not below) this bar — bleeding
        // into and covering that column's icons. Skip it there instead of
        // guessing at vertical-specific values without being able to see
        // the result.
        .padding(.horizontal, isVertical ? 0 : -12)
        .padding(.top, isVertical ? 0 : -10)
        .padding(.bottom, isVertical ? 0 : -4)
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
    private var scrollShortcutDisplay: String {
        if let data = UserDefaults.standard.data(forKey: "scrollCaptureShortcut"),
           let decoded = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return decoded.displayString
        }
        return Shortcut.defaultScrollShortcut.displayString
    }

    var shortcuts: [(key: String, desc: LocalizedStringKey)] {
        [
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
        (scrollShortcutDisplay, "Scroll Capture (full scrollable content)"),
        ("⌘Z", "Undo last drawing action"),
        ("⌘⇧Z", "Redo last undone action"),
        ("⌘C", "Copy screenshot to Clipboard"),
        ("⌘S", "Save As… (choose where to save)"),
        ("Enter", "Complete & Save screenshot locally"),
        ("⌘U", "Complete & Upload screenshot to cloud"),
        ("⌘I", "Trigger AI vision analysis"),
        ("ESC", "Cancel and close capture"),
        ("H", "Toggle this shortcut list")
        ]
    }

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