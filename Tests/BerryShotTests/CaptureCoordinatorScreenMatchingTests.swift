import XCTest
import AppKit
@testable import BerryShot

/// `CaptureCoordinator.screen(containing:)` is the piece "Record App or
/// Window…" uses to find which `NSScreen` a picked window's global frame
/// belongs to, so it can grab the right backdrop screenshot and convert the
/// window's frame into that screen's overlay-local coordinates. It's a pure
/// function of `CGRectDTO`/`NSScreen` bounds, so it's testable without any
/// live capture.
@MainActor
final class CaptureCoordinatorScreenMatchingTests: XCTestCase {
    func testReturnsTheScreenWhoseBoundsContainTheWindowFrameCenter() throws {
        guard let mainScreen = NSScreen.main, let displayID = mainScreen.displayID else {
            throw XCTSkip("No screen available in this test environment")
        }
        let bounds = CGDisplayBounds(displayID)
        // A plausible window frame roughly centered on the screen, in the
        // same CG top-left-origin global coordinate space
        // `WindowDescriptor.frameInScreenPoints` is already in.
        let windowFrame = CGRectDTO(
            x: Double(bounds.midX) - 200,
            y: Double(bounds.midY) - 150,
            width: 400,
            height: 300
        )

        let resolved = CaptureCoordinator.screen(containing: windowFrame)

        XCTAssertEqual(resolved?.displayID, mainScreen.displayID)
    }

    func testReturnsNilForAFrameOffEveryDisplay() {
        let farAwayFrame = CGRectDTO(x: 1_000_000, y: 1_000_000, width: 100, height: 100)
        XCTAssertNil(CaptureCoordinator.screen(containing: farAwayFrame))
    }
}
