import XCTest
@testable import BerryShot

final class ScrollCaptureErrorMapperTests: XCTestCase {
    func testWindowFrameCaptureCancellationMapsToScrollCancellation() {
        let mapped = ScrollCaptureErrorMapper.windowFrameCaptureError(from: CancellationError())

        guard case .cancelled = mapped else {
            return XCTFail("CancellationError must remain a scroll cancellation")
        }
    }
}
