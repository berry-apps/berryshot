import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@MainActor
public protocol CaptureServiceProtocol {
    func captureRegion(_ rect: CGRect) async throws -> CGImage
    func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> CGImage
}

public enum CaptureError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case noDisplayFound
    case noWindowFound
    case windowNotAvailable(windowID: UInt32)
    case windowStale(windowID: UInt32)
    case windowIdentityChanged(windowID: UInt32, expectedBundleIdentifier: String, actualBundleIdentifier: String)
    case captureFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required to capture content."
        case .noDisplayFound:
            return "The requested display is no longer available."
        case .noWindowFound:
            return "The requested window was not found."
        case .windowNotAvailable:
            return "The selected window is no longer available. Refresh the window list and try again."
        case .windowStale:
            return "The selected window became stale before capture. Refresh the window list and try again."
        case .windowIdentityChanged:
            return "The selected window identity changed before capture. Refresh the window list and try again."
        case .captureFailed(let message):
            return "Window capture failed: \(message)"
        }
    }
}
