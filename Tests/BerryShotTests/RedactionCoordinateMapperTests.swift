import CoreGraphics
import XCTest
@testable import BerryShot

/// Coordinate fixtures across scales/origins, per WP5's verification
/// checklist. Every fixture below is a literal, hand-computed expectation —
/// no assertion is derived from the same formula under test.
final class RedactionCoordinateMapperTests: XCTestCase {
    // MARK: - Vision normalized (lower-left, y-up) -> image pixels (top-left, y-down)

    func testVisionBoxAtBottomOfImageMapsToLargerPixelY() {
        // Vision's own bottom-left quadrant (minY 0, maxY 0.5) is the
        // *bottom* half of the image when re-expressed in top-left/y-down
        // pixel space, i.e. the larger y range.
        let pixelRect = RedactionCoordinateMapper.imagePixelRect(
            forVisionNormalizedBox: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            imageWidth: 200,
            imageHeight: 100
        )
        XCTAssertEqual(pixelRect, CGRect(x: 0, y: 50, width: 100, height: 50))
    }

    func testVisionBoxAtTopOfImageMapsToZeroPixelY() {
        // Vision's top quarter (minY 0.5, maxY 1.0) is the *top* of the
        // image in top-left/y-down pixel space, i.e. y starts at 0.
        let pixelRect = RedactionCoordinateMapper.imagePixelRect(
            forVisionNormalizedBox: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5),
            imageWidth: 200,
            imageHeight: 100
        )
        XCTAssertEqual(pixelRect, CGRect(x: 50, y: 0, width: 100, height: 50))
    }

    func testVisionFullImageBoxRoundTrips() {
        let pixelRect = RedactionCoordinateMapper.imagePixelRect(
            forVisionNormalizedBox: CGRect(x: 0, y: 0, width: 1, height: 1),
            imageWidth: 320,
            imageHeight: 240
        )
        XCTAssertEqual(pixelRect, CGRect(x: 0, y: 0, width: 320, height: 240))
    }

    // MARK: - Image pixels -> normalized [0,1]

    func testNormalizedRectDividesByImageDimensions() {
        let normalized = RedactionCoordinateMapper.normalizedRect(
            forImagePixelRect: CGRect(x: 40, y: 20, width: 80, height: 10),
            imageWidth: 400,
            imageHeight: 100
        )
        XCTAssertEqual(normalized, CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1))
    }

    func testNormalizedRectIsZeroForNonPositiveImageSize() {
        let normalized = RedactionCoordinateMapper.normalizedRect(
            forImagePixelRect: CGRect(x: 1, y: 1, width: 1, height: 1),
            imageWidth: 0,
            imageHeight: 100
        )
        XCTAssertEqual(normalized, .zero)
    }

    // MARK: - AX screen-to-window conversion

    func testAXConversionAtOrdinaryOrigin() {
        let contentRect = CGRect(x: 100, y: 100, width: 800, height: 600)
        let elementFrame = CGRect(x: 150, y: 150, width: 50, height: 20)

        let normalized = try? XCTUnwrap(RedactionCoordinateMapper.normalizedRect(
            forElementFrameInScreenPoints: elementFrame,
            windowContentRectInScreenPoints: contentRect
        ))

        XCTAssertEqual(normalized?.minX ?? -1, 50.0 / 800.0, accuracy: 1e-9)
        XCTAssertEqual(normalized?.minY ?? -1, 50.0 / 600.0, accuracy: 1e-9)
        XCTAssertEqual(normalized?.width ?? -1, 50.0 / 800.0, accuracy: 1e-9)
        XCTAssertEqual(normalized?.height ?? -1, 20.0 / 600.0, accuracy: 1e-9)
    }

    /// The conversion is expressed entirely in points and produces a
    /// dimensionless [0,1] fraction, so it is inherently scale-independent:
    /// the same normalized rect, multiplied by a 1x-sized captured image or
    /// a 2x-sized one, must land at the correspondingly scaled pixel
    /// location in both cases.
    func testAXConversionIsConsistentAcross1xAnd2xCapturedPixelSizes() {
        let contentRect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let elementFrame = CGRect(x: 40, y: 30, width: 20, height: 10)
        let normalized = try! XCTUnwrap(RedactionCoordinateMapper.normalizedRect(
            forElementFrameInScreenPoints: elementFrame,
            windowContentRectInScreenPoints: contentRect
        ))

        // 1x: captured pixel image is exactly the content rect's point size.
        let pixelRect1x = CGRect(
            x: normalized.minX * 400, y: normalized.minY * 300,
            width: normalized.width * 400, height: normalized.height * 300
        )
        XCTAssertEqual(pixelRect1x, CGRect(x: 40, y: 30, width: 20, height: 10))

        // 2x: captured pixel image is double the content rect's point size.
        let pixelRect2x = CGRect(
            x: normalized.minX * 800, y: normalized.minY * 600,
            width: normalized.width * 800, height: normalized.height * 600
        )
        XCTAssertEqual(pixelRect2x, CGRect(x: 80, y: 60, width: 40, height: 20))
    }

    func testAXConversionHandlesNegativeDisplayOrigin() {
        // A secondary display positioned to the left of the primary display
        // has a negative x screen origin.
        let contentRect = CGRect(x: -1200, y: -50, width: 800, height: 600)
        let elementFrame = CGRect(x: -1100, y: 100, width: 50, height: 20)

        let normalized = try! XCTUnwrap(RedactionCoordinateMapper.normalizedRect(
            forElementFrameInScreenPoints: elementFrame,
            windowContentRectInScreenPoints: contentRect
        ))

        XCTAssertEqual(normalized.minX, 100.0 / 800.0, accuracy: 1e-9)
        XCTAssertEqual(normalized.minY, 150.0 / 600.0, accuracy: 1e-9)
    }

    /// `SCContentFilter.contentRect` already excludes the title bar/shadow
    /// (per `01-scope-current-state.md`'s known capture gaps about
    /// `filter.contentRect` vs `window.frame`), so no separate title-bar
    /// offset constant is needed here — using the content rect as the
    /// reference frame absorbs it. This fixture simulates that: a content
    /// rect whose origin already starts below where a title bar would have
    /// been, and an element flush with the top of the content area lands at
    /// normalized y ≈ 0, not some nonzero offset.
    func testAXConversionAbsorbsTitleBarOffsetByUsingContentRectOrigin() {
        let contentRect = CGRect(x: 100, y: 120, width: 800, height: 600) // title bar already excluded
        let elementFrame = CGRect(x: 110, y: 120, width: 100, height: 24) // flush with content top

        let normalized = try! XCTUnwrap(RedactionCoordinateMapper.normalizedRect(
            forElementFrameInScreenPoints: elementFrame,
            windowContentRectInScreenPoints: contentRect
        ))

        XCTAssertEqual(normalized.minY, 0, accuracy: 1e-9)
    }

    func testAXConversionClipsAnElementThatPartiallyOverlapsTheContentRect() {
        let contentRect = CGRect(x: 0, y: 0, width: 400, height: 300)
        // Half of this element is above the content rect (e.g. behind the
        // title bar); only the overlapping half should be reflected.
        let elementFrame = CGRect(x: 10, y: -10, width: 40, height: 20)

        let normalized = try! XCTUnwrap(RedactionCoordinateMapper.normalizedRect(
            forElementFrameInScreenPoints: elementFrame,
            windowContentRectInScreenPoints: contentRect
        ))

        XCTAssertEqual(normalized.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(normalized.height, 10.0 / 300.0, accuracy: 1e-9)
    }

    func testAXConversionReturnsNilWhenElementDoesNotOverlapContentRect() {
        let contentRect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let elementFrame = CGRect(x: 1000, y: 1000, width: 10, height: 10)

        XCTAssertNil(RedactionCoordinateMapper.normalizedRect(
            forElementFrameInScreenPoints: elementFrame,
            windowContentRectInScreenPoints: contentRect
        ))
    }

    func testAXConversionReturnsNilForDegenerateContentRect() {
        XCTAssertNil(RedactionCoordinateMapper.normalizedRect(
            forElementFrameInScreenPoints: CGRect(x: 0, y: 0, width: 10, height: 10),
            windowContentRectInScreenPoints: .zero
        ))
    }

    // MARK: - Padding and clamping

    func testPaddedOutsetsOnEverySide() {
        let padded = RedactionCoordinateMapper.padded(CGRect(x: 10, y: 10, width: 20, height: 10), byPixels: 2)
        XCTAssertEqual(padded, CGRect(x: 8, y: 8, width: 24, height: 14))
    }

    func testPaddedWithZeroIsIdentity() {
        let rect = CGRect(x: 10, y: 10, width: 20, height: 10)
        XCTAssertEqual(RedactionCoordinateMapper.padded(rect, byPixels: 0), rect)
    }

    func testClampedToUnitSquareTrimsAnOverflowingRect() {
        let clamped = RedactionCoordinateMapper.clampedToUnitSquare(CGRect(x: 0.9, y: -0.1, width: 0.5, height: 0.3))
        // `CGRect.intersection` computes bounds via min/max arithmetic, so
        // compare components with a small tolerance rather than exact
        // `CGRect` equality, which can differ in the last floating-point bit.
        XCTAssertEqual(clamped.minX, 0.9, accuracy: 1e-9)
        XCTAssertEqual(clamped.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(clamped.width, 0.1, accuracy: 1e-9)
        XCTAssertEqual(clamped.height, 0.2, accuracy: 1e-9)
    }

    func testClampedToUnitSquareIsZeroForRectEntirelyOutside() {
        let clamped = RedactionCoordinateMapper.clampedToUnitSquare(CGRect(x: 2, y: 2, width: 1, height: 1))
        XCTAssertEqual(clamped, .zero)
    }
}
