@preconcurrency import ScreenCaptureKit

/// Confines live ScreenCaptureKit content to a main-actor discovery/capture boundary.
@MainActor
public protocol ShareableContentProviding {
    func onScreenContent() async throws -> SCShareableContent
}

@MainActor
public final class LiveShareableContentProvider: ShareableContentProviding {
    public init() {}

    public func onScreenContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }
}
