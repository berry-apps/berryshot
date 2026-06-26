import Foundation
import AppKit
@preconcurrency import ScreenCaptureKit

// MARK: - Progress

public struct ScrollCaptureProgress {
    public let framesCapture: Int
    public let estimatedProgress: Double // 0.0 ... 1.0
    public let statusMessage: String
}

// MARK: - Error

public enum ScrollCaptureError: LocalizedError {
    case accessibilityDenied
    case noWindowSelected
    case noScrollableAreaFound
    case captureFailed(String)
    case timeout
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Accessibility permission is required for Scroll Capture. Please grant it in System Settings → Privacy & Security → Accessibility."
        case .noWindowSelected:
            return "No target window selected. Please click on a window to capture."
        case .noScrollableAreaFound:
            return "Could not find a scrollable area in the selected window. The window may not have scrollable content."
        case .captureFailed(let msg):
            return "Capture failed: \(msg)"
        case .timeout:
            return "Scroll capture timed out. The content may be too long or the app too slow to respond."
        case .cancelled:
            return "Scroll capture was cancelled."
        }
    }
}

// MARK: - ScrollCaptureManager

@MainActor
public class ScrollCaptureManager: ObservableObject {
    public static let shared = ScrollCaptureManager()

    // Configuration
    public var scrollStep: Int = 8          // Lines per scroll event
    public var scrollDelay: TimeInterval = 0.12 // Seconds to wait after each scroll
    public var maxFrames: Int = 150         // Safety cap to avoid infinite capture
    public var timeout: TimeInterval = 120   // Total operation timeout
    public var stickyHeaderHeight: Int = 0  // Sticky header to strip (pts)
    public var stickyFooterHeight: Int = 0  // Sticky footer to strip (pts)

    // State
    @Published public private(set) var isCapturing = false
    @Published public private(set) var progress = ScrollCaptureProgress(framesCapture: 0, estimatedProgress: 0, statusMessage: "Ready")

    private var isCancelled = false
    private var captureTask: Task<CGImage, Error>?

    private init() {}

    // MARK: - Cancel

    public func cancel() {
        isCancelled = true
        captureTask?.cancel()
    }

    // MARK: - Main Capture Entry Point

    /// Performs a full scroll capture of the given window.
    /// - Parameters:
    ///   - window: The SCWindow to capture.
    ///   - pid: Process ID of the target app (for AX bridge).
    ///   - onProgress: Called on the main thread with progress updates.
    /// - Returns: The stitched CGImage.
    public func captureScrollable(
        window: SCWindow,
        pid: pid_t,
        onProgress: @escaping (ScrollCaptureProgress) -> Void
    ) async throws -> CGImage {
        guard AccessibilityManager.shared.isAccessibilityGranted else {
            throw ScrollCaptureError.accessibilityDenied
        }

        isCapturing = true
        isCancelled = false

        defer {
            isCapturing = false
        }

        let bridge = AccessibilityBridge(pid: pid)

        // Step 1: Find scroll area and scroll to top
        updateProgress(0, frames: 0, message: "Finding scroll area…", onProgress: onProgress)
        bridge.findScrollableArea()

        updateProgress(0, frames: 0, message: "Scrolling to top…", onProgress: onProgress)
        bridge.scrollToTop()
        try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000))

        // Step 2: Capture loop
        var frames: [CGImage] = []
        let startTime = Date()
        _ = bridge.getScrollInfo()
        var consecutiveNoMoveCount = 0

        updateProgress(0, frames: 0, message: "Starting capture…", onProgress: onProgress)

        while !isCancelled {
            // Timeout check
            if Date().timeIntervalSince(startTime) > timeout {
                throw ScrollCaptureError.timeout
            }

            // Frame cap
            if frames.count >= maxFrames {
                break
            }

            // Capture current visible area
            let frame = try await captureWindowFrame(window: window)
            
            // Check if identical to last frame (meaning we reached the bottom)
            if let lastFrame = frames.last {
                if isIdentical(lastFrame, frame) {
                    consecutiveNoMoveCount += 1
                    if consecutiveNoMoveCount >= 2 {
                        // Truly stuck → stop
                        break
                    }
                } else {
                    consecutiveNoMoveCount = 0
                    frames.append(frame)
                }
            } else {
                frames.append(frame)
            }

            let currentInfo = bridge.getScrollInfo()
            let estimatedProgress = min(0.95, Double(frames.count) / 10.0)
            updateProgress(estimatedProgress, frames: frames.count, message: "Capturing frame \(frames.count)…", onProgress: onProgress)

            // Check if we've reached the bottom via Accessibility (only if supported)
            if currentInfo.currentVertical >= 0.999 || (!currentInfo.canScrollDown && currentInfo.currentVertical > 0) {
                break
            }

            // Scroll down by posting CGEvent at the center of the window
            postScrollEvent(deltaY: -Int32(scrollStep * 2), at: CGPoint(x: window.frame.midX, y: window.frame.midY))
            try await Task.sleep(nanoseconds: UInt64(scrollDelay * 1_000_000_000))
        }

        if isCancelled { throw ScrollCaptureError.cancelled }

        guard !frames.isEmpty else {
            throw ScrollCaptureError.captureFailed("No frames were captured")
        }

        // Step 3: Stitch
        updateProgress(0.97, frames: frames.count, message: "Stitching \(frames.count) frames…", onProgress: onProgress)

        var options = ImageStitcher.StitchOptions()
        options.stickyHeaderHeight = stickyHeaderHeight
        options.stickyFooterHeight = stickyFooterHeight
        let viewportHeight = frames.first.map { $0.height } ?? 1000
        options.overlapSearchHeight = viewportHeight
        options.minOverlap = 4
        // Fallback strip: use 90% of viewport height as default overlap guess
        options.fallbackStrip = Int(Double(viewportHeight) * 0.85)

        guard let stitched = ImageStitcher.stitch(frames: frames, options: options) else {
            throw ScrollCaptureError.captureFailed("Image stitching returned nil")
        }

        updateProgress(1.0, frames: frames.count, message: "Done! \(frames.count) frames captured.", onProgress: onProgress)

        return stitched
    }

    // MARK: - Region Capture (Selected Area)

    public func captureRegion(
        rect: CGRect,
        onProgress: @escaping (ScrollCaptureProgress) -> Void
    ) async throws -> CGImage {
        guard AccessibilityManager.shared.isAccessibilityGranted else {
            throw ScrollCaptureError.accessibilityDenied
        }

        isCapturing = true
        isCancelled = false
        defer { isCapturing = false }

        // Find display for rect
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { rect.intersects($0.frame) }) else {
            throw ScrollCaptureError.captureFailed("No display found for selected region")
        }

        var frames: [CGImage] = []
        let startTime = Date()
        var consecutiveIdenticalFrames = 0

        updateProgress(0, frames: 0, message: "Starting region capture…", onProgress: onProgress)

        while !isCancelled {
            if Date().timeIntervalSince(startTime) > timeout { break }
            if frames.count >= maxFrames { break }

            let frame = try await captureDisplayRegion(display: display, rect: rect)

            // Check if identical to last frame (meaning we reached the bottom)
            if let lastFrame = frames.last {
                if isIdentical(lastFrame, frame) {
                    consecutiveIdenticalFrames += 1
                    if consecutiveIdenticalFrames >= 2 {
                        // Reached bottom
                        break
                    }
                } else {
                    consecutiveIdenticalFrames = 0
                    frames.append(frame)
                }
            } else {
                frames.append(frame)
            }

            let estimatedProgress = min(0.95, Double(frames.count) / 10.0)
            updateProgress(estimatedProgress, frames: frames.count, message: "Capturing frame \(frames.count)…", onProgress: onProgress)

            // Scroll down by posting CGEvent at the center of the rect
            postScrollEvent(deltaY: -Int32(scrollStep * 2), at: CGPoint(x: rect.midX, y: rect.midY))
            try await Task.sleep(nanoseconds: UInt64(scrollDelay * 1_000_000_000))
        }

        if isCancelled { throw ScrollCaptureError.cancelled }
        guard !frames.isEmpty else { throw ScrollCaptureError.captureFailed("No frames captured") }

        updateProgress(0.97, frames: frames.count, message: "Stitching \(frames.count) frames…", onProgress: onProgress)

        var options = ImageStitcher.StitchOptions()
        options.overlapSearchHeight = Int(rect.height)
        options.minOverlap = 4
        options.fallbackStrip = Int(Double(rect.height) * 0.85)

        guard let stitched = ImageStitcher.stitch(frames: frames, options: options) else {
            throw ScrollCaptureError.captureFailed("Stitching failed")
        }

        updateProgress(1.0, frames: frames.count, message: "Done!", onProgress: onProgress)
        return stitched
    }

    // MARK: - Frame Capture

    private func captureWindowFrame(window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw ScrollCaptureError.captureFailed(error.localizedDescription)
        }
    }

    private func captureDisplayRegion(display: SCDisplay, rect: CGRect) async throws -> CGImage {
        // Find which windows to include (all visible)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        let myWindows = content.windows.filter { $0.owningApplication?.processID == pid }
        
        let filter = SCContentFilter(display: display, excludingWindows: myWindows)
        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        let displayRect = CGRect(x: rect.minX - display.frame.minX,
                                 y: rect.minY - display.frame.minY,
                                 width: rect.width,
                                 height: rect.height)
        
        config.width = Int(displayRect.width * scale)
        config.height = Int(displayRect.height * scale)
        config.sourceRect = displayRect
        config.showsCursor = false

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw ScrollCaptureError.captureFailed(error.localizedDescription)
        }
    }

    private func postScrollEvent(deltaY: Int32, at point: CGPoint) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .line,
                                  wheelCount: 1,
                                  wheel1: deltaY,
                                  wheel2: 0,
                                  wheel3: 0) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    private func isIdentical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width && a.height == b.height else { return false }
        
        // Compare multiple rows distributed across the image to avoid false positives in whitespace
        let width = min(a.width, 1000)
        let sampleX = (a.width - width) / 2
        
        let yOffsets = [
            a.height / 5,
            (a.height * 2) / 5,
            (a.height * 3) / 5,
            (a.height * 4) / 5
        ]
        
        for y in yOffsets {
            guard let aRow = ImageStitcher.extractPixelRow(from: a, y: y, height: 1, x: sampleX, width: width, samplesPerRow: width/4), // Sample every 4th pixel
                  let bRow = ImageStitcher.extractPixelRow(from: b, y: y, height: 1, x: sampleX, width: width, samplesPerRow: width/4) else {
                return false
            }
            
            var rowMatches = true
            for i in stride(from: 0, to: aRow.count, by: 4) { // Check R, G, B
                if abs(Int(aRow[i]) - Int(bRow[i])) > 15 || 
                   abs(Int(aRow[i+1]) - Int(bRow[i+1])) > 15 || 
                   abs(Int(aRow[i+2]) - Int(bRow[i+2])) > 15 {
                    rowMatches = false
                    break
                }
            }
            
            // If any sampled row is different, the images are not identical
            if !rowMatches {
                return false
            }
        }
        
        // All sampled rows match
        return true
    }

    // MARK: - Progress helper

    private func updateProgress(_ value: Double, frames: Int, message: String, onProgress: @escaping (ScrollCaptureProgress) -> Void) {
        let p = ScrollCaptureProgress(framesCapture: frames, estimatedProgress: value, statusMessage: message)
        self.progress = p
        onProgress(p)
    }
}
