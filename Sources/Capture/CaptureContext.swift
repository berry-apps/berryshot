import CoreGraphics
import Foundation

/// Identifies the kind of capture that produced an image without retaining live
/// ScreenCaptureKit or Accessibility objects.
public enum CaptureSource: String, Codable, Sendable {
    case region
    case window
    case applicationWindow
    case scrollResult
}

/// The privacy policy requested for a capture. WP1 only records the policy; the
/// renderer and detection behavior are introduced in later work packages.
public enum RedactionPolicy: String, Codable, Sendable {
    case none
    case suggest
    case required
}

/// Metadata attached to a final image as it moves through the artifact pipeline.
/// It deliberately contains no `SCWindow`, AX element, or captured pixel data.
public struct CaptureContext: Codable, Sendable, Equatable {
    public let source: CaptureSource
    public let displayID: UInt32?
    public let regionInDisplayPoints: CGRect?
    public let bundleIdentifier: String?
    public let applicationName: String?
    public let windowID: UInt32?
    public let windowTitle: String?
    public let redactionPolicy: RedactionPolicy
    /// User-drawn regions to flatten, normalized to the final image. WP4
    /// only ever populates this from the Region Capture overlay; other
    /// sources carry an empty array until a later work package gives them a
    /// manual-region editor or automatic detection.
    public let manualRedactionRegions: [RedactionRegion]

    public init(
        source: CaptureSource,
        displayID: UInt32? = nil,
        regionInDisplayPoints: CGRect? = nil,
        bundleIdentifier: String? = nil,
        applicationName: String? = nil,
        windowID: UInt32? = nil,
        windowTitle: String? = nil,
        redactionPolicy: RedactionPolicy = .none,
        manualRedactionRegions: [RedactionRegion] = []
    ) {
        self.source = source
        self.displayID = displayID
        self.regionInDisplayPoints = regionInDisplayPoints
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.redactionPolicy = redactionPolicy
        self.manualRedactionRegions = manualRedactionRegions
    }

    public static func region(
        displayID: UInt32?,
        rect: CGRect,
        redactionPolicy: RedactionPolicy = .none,
        manualRedactionRegions: [RedactionRegion] = []
    ) -> CaptureContext {
        CaptureContext(
            source: .region,
            displayID: displayID,
            regionInDisplayPoints: rect,
            redactionPolicy: redactionPolicy,
            manualRedactionRegions: manualRedactionRegions
        )
    }

    public static func window(
        windowID: UInt32,
        bundleIdentifier: String?,
        applicationName: String? = nil,
        windowTitle: String? = nil,
        redactionPolicy: RedactionPolicy = .none,
        manualRedactionRegions: [RedactionRegion] = []
    ) -> CaptureContext {
        CaptureContext(
            source: .window,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            windowID: windowID,
            windowTitle: windowTitle,
            redactionPolicy: redactionPolicy,
            manualRedactionRegions: manualRedactionRegions
        )
    }

    public static func applicationWindow(
        windowID: UInt32,
        bundleIdentifier: String,
        applicationName: String? = nil,
        windowTitle: String? = nil,
        redactionPolicy: RedactionPolicy = .none,
        manualRedactionRegions: [RedactionRegion] = []
    ) -> CaptureContext {
        CaptureContext(
            source: .applicationWindow,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            windowID: windowID,
            windowTitle: windowTitle,
            redactionPolicy: redactionPolicy,
            manualRedactionRegions: manualRedactionRegions
        )
    }

    public static func scrollResult(
        displayID: UInt32? = nil,
        regionInDisplayPoints: CGRect? = nil,
        redactionPolicy: RedactionPolicy = .none,
        manualRedactionRegions: [RedactionRegion] = []
    ) -> CaptureContext {
        CaptureContext(
            source: .scrollResult,
            displayID: displayID,
            regionInDisplayPoints: regionInDisplayPoints,
            redactionPolicy: redactionPolicy,
            manualRedactionRegions: manualRedactionRegions
        )
    }
}
