import XCTest
import AppKit
@testable import BerryShot

/// Regression test for the retain cycle fixed in `CaptureResultWindow.swift`:
/// the result-preview window's own `onClose` closure used to capture its
/// `window` strongly while also being installed (via `contentView`) inside
/// that same window, so `window -> contentView -> view -> onClose -> window`
/// kept the window (and its full-resolution image) alive forever, even after
/// close() was called and the controller was removed from `activeControllers`.
@MainActor
final class CaptureResultWindowMemoryTests: XCTestCase {
    func testControllerAndWindowDeallocateAfterClose() async throws {
        let cgImage = try XCTUnwrap(Self.makeTestImage())

        weak var weakController: CaptureResultWindowController?
        weak var weakWindow: NSWindow?

        do {
            let controller = CaptureResultWindowController(cgImage: cgImage)
            weakController = controller
            weakWindow = controller.window
            controller.window?.close()
        }

        // `close()` posts `willCloseNotification` synchronously, but the
        // observer only schedules a `Task { @MainActor in ... }` to do the
        // actual cleanup — give that task a few run-loop turns to execute.
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertNil(weakController, "CaptureResultWindowController should deallocate once removed from activeControllers after its window closes")
        XCTAssertNil(weakWindow, "NSWindow must not be kept alive by its own content view after close() — that would also pin its full-resolution image in memory forever")
    }

    /// The real-world root cause behind "memory climbs with every capture
    /// and never comes back down, even after sitting idle": nothing ever
    /// closed a previous result window on its own, so leaving each preview
    /// open (rather than clicking Close every time) accumulated full-
    /// resolution images without limit. `leaks` cannot see this because
    /// every window stays *reachable* via `activeControllers` — it's not an
    /// ARC cycle, just unbounded intentional retention. This test proves
    /// the fix: opening more than the cap closes the oldest ones for real
    /// (weak references go nil), instead of merely letting the array grow.
    func testOpeningManyResultWindowsClosesOldestPastTheCap() async throws {
        let cap = 12
        let cgImage = try XCTUnwrap(Self.makeTestImage())

        var weakControllers: [Int: WeakBox] = [:]

        for i in 0..<(cap + 5) {
            let controller = CaptureResultWindowController(cgImage: cgImage)
            weakControllers[i] = WeakBox(controller)
            controller.show()
        }

        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(CaptureResultWindowController.activeControllers.count, cap, "activeControllers should be capped instead of growing without limit")

        for i in 0..<5 {
            XCTAssertNil(weakControllers[i]?.value, "Window #\(i) (oldest, past the cap) should have been force-closed and deallocated")
        }
        for i in 5..<(cap + 5) {
            XCTAssertNotNil(weakControllers[i]?.value, "Window #\(i) is within the cap and should still be open")
        }

        // Clean up the still-open windows this test created so it doesn't
        // leave the shared `activeControllers` state dirty for other tests.
        for controller in CaptureResultWindowController.activeControllers {
            controller.window?.close()
        }
        for _ in 0..<10 { await Task.yield() }
    }

    private final class WeakBox {
        weak var value: CaptureResultWindowController?
        init(_ value: CaptureResultWindowController) { self.value = value }
    }

    private static func makeTestImage() -> CGImage? {
        let width = 10
        let height = 10
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
