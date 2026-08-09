import XCTest
@testable import BerryShot

final class WindowCaptureConfigurationTests: XCTestCase {
    func testPixelSizeUsesCeilingAndNativePointPixelScale() {
        XCTAssertEqual(
            WindowCaptureConfiguration.pixelSize(
                contentRect: CGRectDTO(x: 0, y: 0, width: 100, height: 50),
                pointPixelScale: 1
            ),
            WindowCapturePixelSize(width: 100, height: 50)
        )
        XCTAssertEqual(
            WindowCaptureConfiguration.pixelSize(
                contentRect: CGRectDTO(x: 0, y: 0, width: 100.1, height: 50.1),
                pointPixelScale: 1.5
            ),
            WindowCapturePixelSize(width: 151, height: 76)
        )
        XCTAssertEqual(
            WindowCaptureConfiguration.pixelSize(
                contentRect: CGRectDTO(x: 0, y: 0, width: 100.25, height: 50.25),
                pointPixelScale: 2
            ),
            WindowCapturePixelSize(width: 201, height: 101)
        )
    }

    func testPixelSizeHasOnePixelMinimum() {
        XCTAssertEqual(
            WindowCaptureConfiguration.pixelSize(
                contentRect: CGRectDTO(x: 0, y: 0, width: 0, height: 0),
                pointPixelScale: 2
            ),
            WindowCapturePixelSize(width: 1, height: 1)
        )
    }
}
