import SwiftUI
import AppKit

// MARK: - Progress View Model

@MainActor
public class ScrollCaptureProgressViewModel: ObservableObject {
    @Published public var progress: Double = 0
    @Published public var statusMessage: String = "Starting…"
    @Published public var frameCount: Int = 0
    @Published public var isDone: Bool = false
    @Published public var errorMessage: String? = nil

    public var onCancel: (() -> Void)?
    public init() {}

    public func update(with p: ScrollCaptureProgress) {
        self.progress = p.estimatedProgress
        self.statusMessage = p.statusMessage
        self.frameCount = p.framesCapture
    }
}

// MARK: - Progress Window View

public struct ScrollCaptureProgressView: View {
    @ObservedObject var viewModel: ScrollCaptureProgressViewModel

    public var body: some View {
        VStack(spacing: 20) {
            // Icon + Title
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "scroll.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scroll Capture")
                        .font(.system(size: 15, weight: .bold))
                    Text(viewModel.errorMessage != nil ? "Failed" : (viewModel.isDone ? "Complete" : "In Progress"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if let err = viewModel.errorMessage {
                // Error state
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            } else {
                // Progress bar
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.progress)

                    HStack {
                        Text(viewModel.statusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        if viewModel.frameCount > 0 {
                            Text("\(viewModel.frameCount) frames")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }

            // Bottom buttons
            HStack {
                if !viewModel.isDone && viewModel.errorMessage == nil {
                    Button("Cancel") {
                        viewModel.onCancel?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Progress Panel Controller

@MainActor
public class ScrollCaptureProgressController {
    private var panel: NSPanel?
    public let viewModel = ScrollCaptureProgressViewModel()

    public static let shared = ScrollCaptureProgressController()
    private init() {}

    public func show(onCancel: @escaping () -> Void) {
        viewModel.progress = 0
        viewModel.statusMessage = "Starting…"
        viewModel.frameCount = 0
        viewModel.isDone = false
        viewModel.errorMessage = nil
        viewModel.onCancel = onCancel

        guard panel == nil else {
            panel?.orderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Scroll Capture"
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 3)
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // Exclude this window from screen capture so it never leaks into the scroll-capture frames.
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.center()
        self.panel = panel

        let view = ScrollCaptureProgressView(viewModel: viewModel)
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFront(nil)
    }

    public func update(_ p: ScrollCaptureProgress) {
        viewModel.update(with: p)
    }

    public func finish() {
        viewModel.isDone = true
        viewModel.progress = 1.0
        viewModel.statusMessage = "Done!"
        // Auto-close after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.close()
        }
    }

    /// Keeps the panel open with an indeterminate-feeling "still working"
    /// message and does NOT schedule an auto-close, unlike `finish()`.
    /// Callers that still have async work left (redaction/OCR/persistence
    /// before a result preview can show an already-redacted image) call this
    /// instead of `finish()`, then `close()` themselves once that work ends —
    /// otherwise the progress panel would vanish while the user stares at
    /// nothing for however long redaction takes.
    public func showProcessing(_ message: String) {
        viewModel.isDone = false
        viewModel.errorMessage = nil
        viewModel.statusMessage = message
    }

    public func showError(_ message: String) {
        viewModel.errorMessage = message
        viewModel.isDone = false
        // Auto-close after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.close()
        }
    }

    public func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}
