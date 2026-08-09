import CoreGraphics
import CryptoKit
import XCTest
@testable import BerryShot

final class RedactionRendererTests: XCTestCase {
    // MARK: - Coordinate mapping

    /// `RedactionRegion.normalizedRect` is documented as top-left-origin,
    /// y-down. Core Image's own space is bottom-left-origin, y-up. This test
    /// pins the exact formula so a future edit cannot silently reintroduce a
    /// vertical flip bug, which would redact the wrong half of every image.
    func testPixelRectFlipsTopLeftNormalizedIntoBottomLeftCoreImageSpace() {
        // Top half of a 40x40 image (y: 0..<0.5, top-left convention) must
        // land at Core Image y: 20..<40 (the *upper* range in a bottom-left,
        // y-up space).
        let topHalf = RedactionRenderer.pixelRect(
            for: CGRectDTO(x: 0, y: 0, width: 1, height: 0.5),
            imageWidth: 40,
            imageHeight: 40
        )
        XCTAssertEqual(topHalf, CGRect(x: 0, y: 20, width: 40, height: 20))

        // Bottom half (y: 0.5..<1, top-left convention) must land at Core
        // Image y: 0..<20.
        let bottomHalf = RedactionRenderer.pixelRect(
            for: CGRectDTO(x: 0, y: 0.5, width: 1, height: 0.5),
            imageWidth: 40,
            imageHeight: 40
        )
        XCTAssertEqual(bottomHalf, CGRect(x: 0, y: 0, width: 40, height: 20))
    }

    // MARK: - Pixelate block scaling

    /// A fixed block size (previously always 24px) looks right at one
    /// resolution and wrong everywhere else — too coarse on a small region,
    /// too fine to reliably obscure text on a large capture. Pins the
    /// proportional-with-clamps formula so it cannot silently regress back
    /// to a constant. Per manual QA (`docs/tests/01.md` item 5).
    func testPixellateScaleIsProportionalToSmallerDimensionWithClamps() {
        // Tiny image: proportional value (0.02 * 40 = 0.8) is far below the
        // illegibility floor, so the floor clamp applies.
        XCTAssertEqual(RedactionRenderer.pixellateScale(forImageWidth: 40, height: 40), 12)

        // Mid-size image within the unclamped range: exactly proportional.
        XCTAssertEqual(RedactionRenderer.pixellateScale(forImageWidth: 2000, height: 1000), 20)

        // Huge Retina capture: proportional value (0.02 * 3000 = 60) still
        // under the ceiling — stays proportional rather than degenerating
        // into a handful of giant squares.
        XCTAssertEqual(RedactionRenderer.pixellateScale(forImageWidth: 3000, height: 3000), 60)

        // Very large capture: proportional value would exceed the ceiling,
        // so the ceiling clamp applies.
        XCTAssertEqual(RedactionRenderer.pixellateScale(forImageWidth: 6000, height: 4000), 64)

        // Only the smaller dimension drives the scale, regardless of orientation.
        XCTAssertEqual(
            RedactionRenderer.pixellateScale(forImageWidth: 2000, height: 1000),
            RedactionRenderer.pixellateScale(forImageWidth: 1000, height: 2000)
        )
    }

    // MARK: - Extent preservation

    func testFlattenPreservesExactInputExtentForEveryStyle() throws {
        let renderer = RedactionRenderer()
        let image = makeSplitImage(width: 40, height: 40)
        let region = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 1, height: 0.5), style: .blur)

        for style in RedactionStyle.allCases {
            let region = RedactionRegion(normalizedRect: region.normalizedRect, category: .manual, confidence: 1.0, source: .manual, style: style)
            let output = try renderer.flatten(image, regions: [region])
            XCTAssertEqual(output.width, image.width, "style \(style) changed width")
            XCTAssertEqual(output.height, image.height, "style \(style) changed height")
        }
    }

    func testFlattenWithNoRegionsReturnsTheOriginalImageUnchanged() throws {
        let renderer = RedactionRenderer()
        let image = makeSplitImage(width: 12, height: 12)
        let output = try renderer.flatten(image, regions: [])
        XCTAssertEqual(fingerprint(output), fingerprint(image))
    }

    // MARK: - Solid: exact, deterministic fill

    func testSolidFillsExactlyTheTopRegionAndLeavesTheBottomBitExact() throws {
        let renderer = RedactionRenderer()
        let width = 40, height = 40
        let image = makeSplitImage(width: width, height: height)
        let region = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 1, height: 0.5), style: .solid)

        let output = try renderer.flatten(image, regions: [region])

        // Top rows (raw buffer rows 0..<20) were the checkerboard; solid must
        // overwrite every one of them with the exact same fill color.
        let fillColor = pixel(output, row: 0, col: 0)
        for row in 0..<(height / 2) {
            for col in stride(from: 0, to: width, by: 5) {
                XCTAssertEqual(pixel(output, row: row, col: col), fillColor, "row \(row) col \(col) was not the solid fill color")
            }
        }

        // Bottom rows (raw buffer rows 20..<40) were untouched green and must
        // be bit-for-bit identical to the source.
        for row in (height / 2)..<height {
            for col in stride(from: 0, to: width, by: 5) {
                XCTAssertEqual(pixel(output, row: row, col: col), pixel(image, row: row, col: col), "row \(row) col \(col) outside the mask changed")
            }
        }
    }

    func testSolidOnlyChangesPixelsInsideAnOffCenterRegion() throws {
        let renderer = RedactionRenderer()
        let width = 40, height = 40
        let image = makeSplitImage(width: width, height: height)
        // A small rectangle entirely within the top-left quadrant.
        let region = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0.1, y: 0.1, width: 0.2, height: 0.2), style: .solid)

        let output = try renderer.flatten(image, regions: [region])

        // A sample point comfortably inside the masked rectangle changed.
        XCTAssertNotEqual(pixel(output, row: 6, col: 6), pixel(image, row: 6, col: 6))
        // A sample point comfortably outside it (bottom-right corner) is untouched.
        XCTAssertEqual(pixel(output, row: 39, col: 39), pixel(image, row: 39, col: 39))
    }

    // MARK: - Blur / pixelate: changed inside, unchanged outside

    func testBlurChangesPixelsInsideTheRegionAndLeavesOutsideBitExact() throws {
        let renderer = RedactionRenderer()
        let image = makeSplitImage(width: 60, height: 60)
        let region = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 1, height: 0.5), style: .blur)

        let output = try renderer.flatten(image, regions: [region])

        // A sharp edge inside the checkerboard must have been smoothed toward
        // an intermediate value rather than staying pure black/white.
        let originalEdge = pixel(image, row: 6, col: 6)
        let blurredEdge = pixel(output, row: 6, col: 6)
        XCTAssertNotEqual(originalEdge, blurredEdge, "blur did not change a pixel inside the masked region")

        // Untouched (bottom, green) rows must be bit-for-bit identical.
        for col in stride(from: 0, to: 60, by: 7) {
            XCTAssertEqual(pixel(output, row: 59, col: col), pixel(image, row: 59, col: col))
        }
    }

    func testPixelateChangesPixelsInsideTheRegionAndLeavesOutsideBitExact() throws {
        let renderer = RedactionRenderer()
        let image = makeNoiseImage(width: 48, height: 48)
        let region = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 1, height: 0.5), style: .pixelate)

        let output = try renderer.flatten(image, regions: [region])

        // Adjacent pixels that were unique noise become uniform within a
        // pixellate block, proving blocking occurred.
        let a = pixel(output, row: 4, col: 4)
        let b = pixel(output, row: 4, col: 5)
        XCTAssertEqual(a, b, "adjacent pixels inside the pixellated region were not blocked together")

        // Untouched (bottom) rows must be bit-for-bit identical to source.
        for col in stride(from: 0, to: 48, by: 5) {
            XCTAssertEqual(pixel(output, row: 47, col: col), pixel(image, row: 47, col: col))
        }
    }

    // MARK: - Multiple regions in one pass

    func testFlattenAppliesMultipleDistinctRegionsInOneCall() throws {
        let renderer = RedactionRenderer()
        let width = 40, height = 40
        let image = makeSplitImage(width: width, height: height)
        let top = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 0.5, height: 0.1), style: .solid)
        let bottom = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0.5, y: 0.9, width: 0.5, height: 0.1), style: .solid)

        let output = try renderer.flatten(image, regions: [top, bottom])

        XCTAssertNotEqual(pixel(output, row: 0, col: 0), pixel(image, row: 0, col: 0))
        XCTAssertNotEqual(pixel(output, row: 39, col: 39), pixel(image, row: 39, col: 39))
        // A point untouched by either region stays identical.
        XCTAssertEqual(pixel(output, row: 20, col: 0), pixel(image, row: 20, col: 0))
    }

    // MARK: - Region merge

    func testMergerUnionsOverlappingRegionsOfTheSameStyle() throws {
        let a = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 0.3, height: 0.3), style: .blur)
        let b = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0.2, y: 0.2, width: 0.3, height: 0.3), style: .blur)

        let merged = RedactionRegionMerger.merge([a, b])

        XCTAssertEqual(merged.count, 1)
        let rect = try XCTUnwrap(merged.first).normalizedRect.cgRect
        XCTAssertEqual(rect, a.normalizedRect.cgRect.union(b.normalizedRect.cgRect))
    }

    func testMergerKeepsNonOverlappingRegionsDistinct() {
        let a = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 0.1, height: 0.1), style: .solid)
        let b = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0.8, y: 0.8, width: 0.1, height: 0.1), style: .solid)

        let merged = RedactionRegionMerger.merge([a, b])

        XCTAssertEqual(merged.count, 2)
    }

    /// WP5 mixes automatically detected categories into the same merge pass
    /// as manual regions. When two overlapping regions of different
    /// categories merge, the result must keep the *higher-confidence*
    /// contributor's category/source/confidence, never silently fall back to
    /// `.manual` (which is what the pre-WP5 merger unconditionally did).
    func testMergerKeepsTheHigherConfidenceCategoryWhenAutomaticAndManualRegionsOverlap() throws {
        let manual = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 0.3, height: 0.3), style: .solid) // confidence 1.0
        let email = RedactionRegion(
            normalizedRect: CGRectDTO(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
            category: .email,
            confidence: 0.7,
            source: .visionOCR,
            style: .solid
        )

        let merged = RedactionRegionMerger.merge([manual, email])

        XCTAssertEqual(merged.count, 1)
        let result = try XCTUnwrap(merged.first)
        // Manual (confidence 1.0) outranks the automatic email match (0.7).
        XCTAssertEqual(result.category, .manual)
        XCTAssertEqual(result.source, .manual)
        XCTAssertEqual(result.confidence, 1.0)
        XCTAssertEqual(result.normalizedRect.cgRect, manual.normalizedRect.cgRect.union(email.normalizedRect.cgRect))
    }

    func testMergerKeepsTheStrongerAutomaticCategoryWhenTwoDetectedRegionsOverlap() throws {
        let phone = RedactionRegion(
            normalizedRect: CGRectDTO(x: 0, y: 0, width: 0.3, height: 0.3),
            category: .phoneNumber,
            confidence: 0.6,
            source: .visionOCR,
            style: .blur
        )
        let card = RedactionRegion(
            normalizedRect: CGRectDTO(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
            category: .creditCard,
            confidence: 0.9,
            source: .visionOCR,
            style: .blur
        )

        let merged = RedactionRegionMerger.merge([phone, card])

        XCTAssertEqual(merged.count, 1)
        let result = try XCTUnwrap(merged.first)
        XCTAssertEqual(result.category, .creditCard)
        XCTAssertEqual(result.confidence, 0.9)
    }

    func testMergerDoesNotCollapseOverlappingRegionsWithDifferentStyles() {
        let a = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 0.3, height: 0.3), style: .blur)
        let b = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0.1, y: 0.1, width: 0.3, height: 0.3), style: .solid)

        let merged = RedactionRegionMerger.merge([a, b])

        XCTAssertEqual(merged.count, 2, "different styles must never be silently collapsed into one treatment")
        XCTAssertTrue(merged.contains { $0.style == .blur })
        XCTAssertTrue(merged.contains { $0.style == .solid })
    }

    // MARK: - Fixtures

    /// Raw buffer rows 0..<height/2 are a black/white checkerboard (useful
    /// for observing blur smoothing); rows height/2..<height are solid green.
    /// Row 0 is the top of the image as normally viewed — verified against
    /// this toolchain's `CGContext`/`CGImage` behavior before writing this
    /// suite (see the WP4 issue's "Documentation consulted" section).
    private func makeSplitImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // CGContext user space is bottom-left/y-up: y:0..<height/2 draws the
        // *bottom* half visually, y:height/2..<height draws the *top* half.
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))

        let checkerCell = 4
        var row = 0
        var y = height / 2
        while y < height {
            var col = 0
            var x = 0
            while x < width {
                let isWhite = (row + col) % 2 == 0
                ctx.setFillColor(isWhite ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: checkerCell, height: checkerCell))
                col += 1
                x += checkerCell
            }
            row += 1
            y += checkerCell
        }
        return ctx.makeImage()!
    }

    /// A fixture with a distinct color per pixel in the top half, so
    /// pixellate's block-averaging is observable, and a uniform bottom half
    /// to check for unwanted bleed outside the masked region.
    private func makeNoiseImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))

        var seed: UInt64 = 42
        func nextUnit() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1
            return CGFloat((seed >> 33) % 1000) / 1000
        }
        var y = height / 2
        while y < height {
            var x = 0
            while x < width {
                ctx.setFillColor(CGColor(red: nextUnit(), green: nextUnit(), blue: nextUnit(), alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                x += 1
            }
            y += 1
        }
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, row: Int, col: Int) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        let bytesPerRow = image.bytesPerRow
        let offset = row * bytesPerRow + col * 4
        return [data[offset], data[offset + 1], data[offset + 2]]
    }

    private func fingerprint(_ image: CGImage) -> String {
        guard let providerData = image.dataProvider?.data else { return "" }
        return SHA256.hash(data: providerData as Data).map { String(format: "%02x", $0) }.joined()
    }
}
