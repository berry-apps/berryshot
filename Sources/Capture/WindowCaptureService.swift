import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

public struct WindowCapturePixelSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum WindowCaptureConfiguration {
    public static func pixelSize(contentRect: CGRectDTO, pointPixelScale: Double) -> WindowCapturePixelSize {
        let scale = max(0, pointPixelScale)
        return WindowCapturePixelSize(
            width: max(1, Int(ceil(contentRect.width * scale))),
            height: max(1, Int(ceil(contentRect.height * scale)))
        )
    }
}

/// Pixel data and metadata resolved during the same capture snapshot. This remains in-process.
public struct RawCapturedWindow {
    public let image: CGImage
    public let descriptor: WindowDescriptor
    public let pointPixelScale: Double
    public let contentRectInPoints: CGRectDTO
}

/// The sole independent-window screenshot primitive. It never falls back to a desktop crop.
@MainActor
public final class WindowCaptureService {
    public static let shared = WindowCaptureService()

    private let contentProvider: any ShareableContentProviding
    private let ownBundleIdentifier: String?
    /// A fixed value is useful for deterministic tests; production resolves it per discovery snapshot.
    private let configuredFrontmostProcessID: Int32?

    public init(
        contentProvider: any ShareableContentProviding = LiveShareableContentProvider(),
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        frontmostProcessID: Int32? = nil
    ) {
        self.contentProvider = contentProvider
        self.ownBundleIdentifier = ownBundleIdentifier
        self.configuredFrontmostProcessID = frontmostProcessID
    }

    public func discoverWindows() async throws -> [WindowDescriptor] {
        let content = try await contentProvider.onScreenContent()
        return descriptors(from: content)
    }

    public func discoverApplications() async throws -> [ApplicationDescriptor] {
        ApplicationWindowDiscovery.applicationDescriptors(from: try await discoverWindows())
    }

    public func captureWindow(_ selectedDescriptor: WindowDescriptor) async throws -> RawCapturedWindow {
        let (window, currentDescriptor) = try await resolvedWindow(for: selectedDescriptor)
        return try await capture(window: window, descriptor: currentDescriptor)
    }

    /// Resolves a live ScreenCaptureKit window only for the duration of one
    /// operation. UI and callers retain `WindowDescriptor`, never `SCWindow`.
    public func withResolvedWindow<T>(
        _ selectedDescriptor: WindowDescriptor,
        operation: (SCWindow) async throws -> T
    ) async throws -> T {
        let (window, _) = try await resolvedWindow(for: selectedDescriptor)
        return try await operation(window)
    }

    private func resolvedWindow(for selectedDescriptor: WindowDescriptor) async throws -> (SCWindow, WindowDescriptor) {
        let content = try await contentProvider.onScreenContent()
        guard let window = content.windows.first(where: { $0.windowID == selectedDescriptor.id }) else {
            throw CaptureError.windowNotAvailable(windowID: selectedDescriptor.id)
        }
        guard let actualBundleIdentifier = window.owningApplication?.bundleIdentifier else {
            throw CaptureError.windowNotAvailable(windowID: selectedDescriptor.id)
        }
        guard actualBundleIdentifier == selectedDescriptor.bundleIdentifier else {
            throw CaptureError.windowIdentityChanged(
                windowID: selectedDescriptor.id,
                expectedBundleIdentifier: selectedDescriptor.bundleIdentifier,
                actualBundleIdentifier: actualBundleIdentifier
            )
        }
        guard window.owningApplication?.processID == selectedDescriptor.processID else {
            // PID is not durable identity; it merely tells the caller that this discovery
            // snapshot is stale, rather than silently capturing a newly launched instance.
            throw CaptureError.windowStale(windowID: selectedDescriptor.id)
        }

        guard let currentDescriptor = ApplicationWindowDiscovery.eligibleWindowDescriptors(
            from: [record(for: window, frontmostProcessID: frontmostProcessID)],
            excludingBundleIdentifier: ownBundleIdentifier
        ).first else {
            throw CaptureError.windowNotAvailable(windowID: selectedDescriptor.id)
        }
        return (window, currentDescriptor)
    }

    /// Used by Scroll Capture while it owns the selected live window for one operation.
    public func captureImage(window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = screenshotConfiguration(for: filter)
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CaptureError.captureFailed(message: error.localizedDescription)
        }
    }

    private func capture(window: SCWindow, descriptor: WindowDescriptor) async throws -> RawCapturedWindow {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let contentRect = CGRectDTO(filter.contentRect)
        let pointPixelScale = Double(filter.pointPixelScale)
        let image = try await captureImage(window: window)
        return RawCapturedWindow(
            image: image,
            descriptor: descriptor,
            pointPixelScale: pointPixelScale,
            contentRectInPoints: contentRect
        )
    }

    private func screenshotConfiguration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let size = WindowCaptureConfiguration.pixelSize(
            contentRect: CGRectDTO(filter.contentRect),
            pointPixelScale: Double(filter.pointPixelScale)
        )
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        configuration.preservesAspectRatio = true
        return configuration
    }

    private func descriptors(from content: SCShareableContent) -> [WindowDescriptor] {
        let activeProcessID = self.frontmostProcessID
        return ApplicationWindowDiscovery.eligibleWindowDescriptors(
            from: content.windows.map { record(for: $0, frontmostProcessID: activeProcessID) },
            excludingBundleIdentifier: ownBundleIdentifier
        )
    }

    private var frontmostProcessID: Int32? {
        configuredFrontmostProcessID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private func record(for window: SCWindow, frontmostProcessID: Int32?) -> WindowDiscoveryRecord {
        let application = window.owningApplication
        return WindowDiscoveryRecord(
            windowID: window.windowID,
            bundleIdentifier: application?.bundleIdentifier,
            applicationName: application?.applicationName,
            processID: application?.processID ?? 0,
            title: window.title,
            frameInScreenPoints: CGRectDTO(window.frame),
            isOnScreen: window.isOnScreen,
            isFrontmost: application?.processID == frontmostProcessID
        )
    }
}
