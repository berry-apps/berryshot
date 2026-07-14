import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@MainActor
public protocol CaptureServiceProtocol {
    func captureRegion(_ rect: CGRect) async throws -> CGImage
    func captureWindow(_ windowID: CGWindowID) async throws -> CGImage
    func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> CGImage
}

public enum CaptureError: Error {
    case permissionDenied
    case noDisplayFound
    case noWindowFound
    case captureFailed
}
