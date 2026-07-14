import SwiftUI
@preconcurrency import ScreenCaptureKit
import AppKit

// MARK: - Window Info Model

public struct WindowInfo: Identifiable, Hashable {
    public let id: CGWindowID
    public let appName: String
    public let windowTitle: String
    public let pid: pid_t
    public let scWindow: SCWindow
    public var thumbnail: NSImage?

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool { lhs.id == rhs.id }
}

// MARK: - WindowSelectorViewModel

@MainActor
public class WindowSelectorViewModel: ObservableObject {
    @Published public var windows: [WindowInfo] = []
    @Published public var isLoading = true
    @Published public var selectedWindow: WindowInfo? = nil
    @Published public var errorMessage: String? = nil

    public init() {}

    public func loadWindows() async {
        isLoading = true
        errorMessage = nil

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            var infos: [WindowInfo] = []

            for window in content.windows {
                guard let app = window.owningApplication,
                      window.frame.width > 100,
                      window.frame.height > 100 else { continue }

                let title = window.title ?? "(No Title)"
                let appName = app.applicationName
                var info = WindowInfo(
                    id: window.windowID,
                    appName: appName,
                    windowTitle: title,
                    pid: app.processID,
                    scWindow: window
                )

                // Attempt to capture thumbnail
                if let thumb = try? await captureThumbnail(window: window) {
                    info.thumbnail = thumb
                }

                infos.append(info)
            }

            // Sort: active app first, then by app name
            let activeAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            infos.sort {
                if $0.pid == activeAppPID { return true }
                if $1.pid == activeAppPID { return false }
                return $0.appName < $1.appName
            }

            self.windows = infos
        } catch {
            self.errorMessage = "Failed to load windows: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func captureThumbnail(window: SCWindow) async throws -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = 180
        config.height = 120
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: image, size: NSSize(width: 180, height: 120))
    }
}

// MARK: - WindowSelectorView

public struct WindowSelectorView: View {
    @ObservedObject var viewModel: WindowSelectorViewModel
    let onSelect: (WindowInfo) -> Void
    let onCancel: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)
    ]

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "scroll")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scroll Capture")
                        .font(.system(size: 16, weight: .bold))
                    Text("Select a window to capture its full scrollable content")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading windows…")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else if let err = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(err)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await viewModel.loadWindows() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else if viewModel.windows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No windows found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.windows) { info in
                            WindowCardView(
                                info: info,
                                isSelected: viewModel.selectedWindow?.id == info.id
                            ) {
                                viewModel.selectedWindow = info
                                onSelect(info)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 440, idealHeight: 520)
        .background(Color(NSColor.controlBackgroundColor))
        .task {
            await viewModel.loadWindows()
        }
    }
}

// MARK: - WindowCardView

struct WindowCardView: View {
    let info: WindowInfo
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.quaternaryLabelColor))
                    .aspectRatio(16/9, contentMode: .fit)

                if let thumb = info.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    // App icon
                    if let appIcon = NSRunningApplication(processIdentifier: info.pid)?.icon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text(info.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Text(info.windowTitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected
                      ? Color.blue.opacity(0.12)
                      : (isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.08) : Color(NSColor.windowBackgroundColor)))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.blue.opacity(0.4) : Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hover in isHovered = hover }
        .onTapGesture { onTap() }
    }
}

// MARK: - Window Selector Panel Controller

@MainActor
public class WindowSelectorPanelController {
    private var panel: NSPanel?
    private var viewModel: WindowSelectorViewModel?
    private var closeObserver: NSObjectProtocol?

    public static let shared = WindowSelectorPanelController()
    private init() {}

    public func show(onSelect: @escaping (WindowInfo) -> Void) {
        // If a panel already exists and is still on screen, just bring it forward.
        // If it exists but is no longer visible (e.g. it was closed via the native
        // close button, which does NOT route through close()), reset our state so a
        // fresh panel can be created instead of being blocked forever.
        if let existing = panel {
            if existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            resetState()
        }

        let vm = WindowSelectorViewModel()
        viewModel = vm

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Scroll Capture — Select Window"
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.center()
        panel.isReleasedWhenClosed = false
        self.panel = panel

        let view = WindowSelectorView(
            viewModel: vm,
            onSelect: { [weak self] info in
                self?.close()
                onSelect(info)
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )

        panel.contentView = NSHostingView(rootView: view)

        // Whenever the panel closes for ANY reason (Cancel button, window selection,
        // or the native red close button), reset our state so the next show() works.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resetState()
            }
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        panel?.orderOut(nil)
        panel?.close()
        resetState()
    }

    private func resetState() {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        panel = nil
        viewModel = nil
    }
}
