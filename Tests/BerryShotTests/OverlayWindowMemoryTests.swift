import XCTest
import AppKit
@testable import BerryShot

/// `OverlayWindowController` holds the full, un-cropped screen capture (by
/// far the largest single image in the app) for the duration of every single
/// capture session — created fresh in `CaptureCoordinator.startCapture()`
/// and torn down via `hide()`. If it doesn't fully deallocate, every capture
/// permanently pins one whole-screen image in memory, which would explain
/// memory that climbs with capture count and never comes back down.
@MainActor
final class OverlayWindowMemoryTests: XCTestCase {
    func testControllerWindowAndViewModelDeallocateAfterHide() async throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("No screen available in this test environment")
        }
        let cgImage = try XCTUnwrap(Self.makeTestImage(width: 1200, height: 800))

        weak var weakController: OverlayWindowController?
        weak var weakWindow: NSWindow?
        weak var weakViewModel: OverlayViewModel?

        do {
            let controller = OverlayWindowController(cgImage: cgImage, display: screen)
            weakController = controller
            weakWindow = controller.window
            weakViewModel = controller.viewModel
            controller.show()
            for _ in 0..<5 { await Task.yield() }
            controller.hide()
        }

        for _ in 0..<15 { await Task.yield() }

        XCTAssertNil(weakController, "OverlayWindowController should deallocate after hide()")
        XCTAssertNil(weakWindow, "OverlayWindow (and its full-screen backing image) should deallocate after hide() — if it doesn't, every single capture session permanently leaks one whole-screen image")
        XCTAssertNil(weakViewModel, "OverlayViewModel should deallocate after hide()")
    }

    private static func makeTestImage(width: Int, height: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
