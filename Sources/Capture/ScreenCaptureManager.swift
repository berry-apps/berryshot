import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@MainActor
public class ScreenCaptureManager: CaptureServiceProtocol {
    public init() {}
    
    public func captureRegion(_ rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw CaptureError.noDisplayFound
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        // sourceRect is in points
        configuration.sourceRect = rect
        // Use exact hardware scale to get physical pixels
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(rect.width * scale)
        configuration.height = Int(rect.height * scale)
        configuration.showsCursor = false
        
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return image
    }
    
    public func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplayFound
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        // Use pointPixelScale to get the exact hardware scaling factor of the display
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        configuration.showsCursor = false
        
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return image
    }
}
