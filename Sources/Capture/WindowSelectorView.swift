import SwiftUI
import AppKit

// MARK: - Window Info Model

public struct WindowInfo: Identifiable, Hashable {
    /// The selector retains only this value descriptor. A live capture object
    /// is resolved by `WindowCaptureService` immediately before scroll capture.
    public let descriptor: WindowDescriptor

    public var id: UInt32 { descriptor.id }
    public var appName: String { descriptor.applicationName }
    public var windowTitle: String { descriptor.title }
    public var pid: pid_t { descriptor.processID }
}

/// Describes how the same discovery UI is being used. Scroll capture keeps its
/// original one-window workflow, while single-frame capture can also group the
/// discovered windows by application.
public enum WindowSelectorPresentationMode: Sendable, Equatable {
    case scrollCapture
    case singleFrameCapture

    fileprivate var title: String {
        switch self {
        case .scrollCapture: "Scroll Capture"
        case .singleFrameCapture: "Capture App or Window"
        }
    }

    fileprivate var subtitle: String {
        switch self {
        case .scrollCapture: "Select a window to capture its full scrollable content"
        case .singleFrameCapture: "Select one window, or capture eligible windows from one app"
        }
    }

    fileprivate var symbolName: String {
        switch self {
        case .scrollCapture: "scroll"
        case .singleFrameCapture: "macwindow.on.rectangle"
        }
    }

    fileprivate var panelTitle: String {
        switch self {
        case .scrollCapture: "Scroll Capture — Select Window"
        case .singleFrameCapture: "Capture App or Window"
        }
    }
}

public struct ApplicationInfo: Identifiable, Hashable {
    public let descriptor: ApplicationDescriptor
    public let windows: [WindowInfo]

    public init(descriptor: ApplicationDescriptor, windows: [WindowInfo]) {
        self.descriptor = descriptor
        self.windows = windows
    }

    public var id: String { descriptor.id }
    public var appName: String { descriptor.applicationName }
    public var windowCount: Int { descriptor.windowCount }
    public var frontmostWindow: WindowInfo? { windows.first(where: { $0.descriptor.isFrontmost }) }
}

public enum WindowSelectorSelection {
    case window(WindowInfo)
    case application(ApplicationInfo, policy: ApplicationCapturePolicy)
}

/// A deterministic translation of a UI selection into the exact descriptors
/// that may be captured. It deliberately never substitutes a different window
/// if the selected descriptor is no longer available when the capture starts.
public enum ApplicationWindowCaptureRoute: Equatable {
    case selectedWindow(WindowDescriptor)
    case applicationWindow(WindowDescriptor)
    case applicationWindows([WindowDescriptor])
}

public enum ApplicationWindowCaptureRouter {
    public static func route(for selection: WindowSelectorSelection) -> ApplicationWindowCaptureRoute? {
        switch selection {
        case let .window(window):
            return .selectedWindow(window.descriptor)
        case let .application(application, .frontmostWindow):
            guard let window = application.frontmostWindow else { return nil }
            return .applicationWindow(window.descriptor)
        case let .application(application, .allOnScreenWindows):
            return .applicationWindows(application.windows.map(\.descriptor))
        }
    }
}

// MARK: - WindowSelectorViewModel

/// The selector needs discovery only; independent-window capture remains owned
/// by `WindowCaptureService` and is never performed for every listed window.
@MainActor
public protocol WindowDiscovering {
    func discoverWindows() async throws -> [WindowDescriptor]
}

extension WindowCaptureService: WindowDiscovering {}

@MainActor
public class WindowSelectorViewModel: ObservableObject {
    @Published public var windows: [WindowInfo] = []
    @Published public var applications: [ApplicationInfo] = []
    @Published public var isLoading = true
    @Published public var selectedWindow: WindowInfo? = nil
    @Published public var errorMessage: String? = nil
    @Published public var noticeMessage: String? = nil
    @Published public var selectedSingleFrameTab: SingleFrameSelectorTab = .applications

    private let windowDiscovery: any WindowDiscovering
    public let mode: WindowSelectorPresentationMode

    public init(
        mode: WindowSelectorPresentationMode = .scrollCapture,
        windowDiscovery: any WindowDiscovering = WindowCaptureService.shared,
        noticeMessage: String? = nil
    ) {
        self.mode = mode
        self.windowDiscovery = windowDiscovery
        self.noticeMessage = noticeMessage
    }

    public func loadWindows() async {
        isLoading = true
        errorMessage = nil

        do {
            let descriptors = try await windowDiscovery.discoverWindows()
            self.windows = descriptors.map(WindowInfo.init(descriptor:))
            self.applications = ApplicationWindowDiscovery.applicationDescriptors(from: descriptors).map { application in
                ApplicationInfo(
                    descriptor: application,
                    windows: self.windows.filter { $0.descriptor.bundleIdentifier == application.id }
                )
            }
        } catch {
            self.windows = []
            self.applications = []
            self.errorMessage = "Failed to load windows: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

public enum SingleFrameSelectorTab: String, CaseIterable, Identifiable, Equatable {
    case applications = "Apps"
    case windows = "Windows"

    public var id: String { rawValue }
}

// MARK: - WindowSelectorView

public struct WindowSelectorView: View {
    @ObservedObject var viewModel: WindowSelectorViewModel
    let onSelect: (WindowSelectorSelection) -> Void
    let onCancel: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)
    ]

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: viewModel.mode.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.mode.title)
                        .font(.system(size: 16, weight: .bold))
                    Text(viewModel.mode.subtitle)
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
                selectorContents
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 440, idealHeight: 520)
        .background(Color(NSColor.controlBackgroundColor))
        .task {
            await viewModel.loadWindows()
        }
    }

    @ViewBuilder
    private var selectorContents: some View {
        switch viewModel.mode {
        case .scrollCapture:
            windowGrid
        case .singleFrameCapture:
            VStack(spacing: 0) {
                if let notice = viewModel.noticeMessage {
                    Label(notice, systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(NSColor.controlBackgroundColor))
                }

                Picker("Capture target", selection: $viewModel.selectedSingleFrameTab) {
                    ForEach(SingleFrameSelectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(16)

                if viewModel.selectedSingleFrameTab == .applications {
                    applicationGrid
                } else {
                    windowGrid
                }
            }
        }
    }

    private var windowGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.windows) { info in
                    WindowCardView(
                        info: info,
                        isSelected: viewModel.selectedWindow?.id == info.id
                    ) {
                        viewModel.selectedWindow = info
                        onSelect(.window(info))
                    }
                }
            }
            .padding(16)
        }
    }

    private var applicationGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.applications) { application in
                    ApplicationCardView(application: application, onSelect: onSelect)
                }
            }
            .padding(16)
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

                // Thumbnails are intentionally deferred. Capturing every
                // discovered window would eagerly allocate images and cross the
                // live ScreenCaptureKit boundary before the user selects one.
                Image(systemName: "macwindow")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
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

struct ApplicationCardView: View {
    let application: ApplicationInfo
    let onSelect: (WindowSelectorSelection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let appIcon = NSRunningApplication(processIdentifier: application.descriptor.processID)?.icon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.dashed")
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(application.windowCount) eligible window\(application.windowCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }

            if application.frontmostWindow != nil {
                Button("Capture Frontmost Window") {
                    onSelect(.application(application, policy: .frontmostWindow))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Capture All Windows") {
                onSelect(.application(application, policy: .allOnScreenWindows))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(application.appName), \(application.windowCount) eligible windows")
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

    public func show(
        mode: WindowSelectorPresentationMode = .scrollCapture,
        noticeMessage: String? = nil,
        onSelect: @escaping (WindowSelectorSelection) -> Void
    ) {
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

        let vm = WindowSelectorViewModel(mode: mode, noticeMessage: noticeMessage)
        viewModel = vm

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = mode.panelTitle
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
