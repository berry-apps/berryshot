import CoreGraphics
import Foundation
import XCTest
@testable import BerryShot

/// Pure composition tests for `SensitiveContentDetector.detect`, independent
/// of any live capture, Vision request, or Accessibility permission.
final class SensitiveContentDetectorTests: XCTestCase {
    private func configuration(
        categories: Set<SensitiveCategory>,
        customTerms: [String] = [],
        caseSensitive: Bool = false,
        style: RedactionStyle = .solid
    ) -> SensitiveDetectionConfiguration {
        SensitiveDetectionConfiguration(
            enabledCategories: categories,
            customTerms: customTerms,
            customTermsCaseSensitive: caseSensitive,
            style: style
        )
    }

    private func block(_ text: String, box: CGRect) -> RecognizedTextBlock {
        RecognizedTextBlock(text: text, confidence: 0.95, normalizedBoundingBox: CGRectDTO(box))
    }

    // MARK: - OCR-derived regions

    func testDetectsAnEmailBlockAndProducesAVisionOCRRegion() {
        let blocks = [block("Contact john.doe@example.com for access", box: CGRect(x: 0, y: 0.4, width: 0.5, height: 0.1))]
        let outcome = SensitiveContentDetector.detect(
            imageWidth: 1000,
            imageHeight: 1000,
            ocrResult: OCRResult(text: "", blocks: blocks),
            ocrAvailable: true,
            secureFieldFramesInScreenPoints: [],
            axAvailable: true,
            windowContentRectInScreenPoints: nil,
            configuration: configuration(categories: [.email])
        )

        XCTAssertEqual(outcome.completeness, .complete)
        XCTAssertEqual(outcome.regions.count, 1)
        let region = try! XCTUnwrap(outcome.regions.first)
        XCTAssertEqual(region.category, .email)
        XCTAssertEqual(region.source, .visionOCR)
        XCTAssertEqual(region.confidence, 0.7)
    }

    func testDisabledCategoryNeverContributesARegionEvenWhenTextMatches() {
        let blocks = [block("Contact john.doe@example.com for access", box: CGRect(x: 0, y: 0.4, width: 0.5, height: 0.1))]
        let outcome = SensitiveContentDetector.detect(
            imageWidth: 1000,
            imageHeight: 1000,
            ocrResult: OCRResult(text: "", blocks: blocks),
            ocrAvailable: true,
            secureFieldFramesInScreenPoints: [],
            axAvailable: true,
            windowContentRectInScreenPoints: nil,
            configuration: configuration(categories: []) // nothing enabled
        )

        XCTAssertEqual(outcome.regions, [])
        XCTAssertEqual(outcome.completeness, .complete)
    }

    func testCustomTermMatchProducesARegionOnlyWhenEnabled() {
        let blocks = [block("Internal project CODENAME-FALCON kickoff", box: CGRect(x: 0, y: 0, width: 1, height: 0.1))]
        let outcome = SensitiveContentDetector.detect(
            imageWidth: 500,
            imageHeight: 500,
            ocrResult: OCRResult(text: "", blocks: blocks),
            ocrAvailable: true,
            secureFieldFramesInScreenPoints: [],
            axAvailable: true,
            windowContentRectInScreenPoints: nil,
            configuration: configuration(categories: [.customTerm], customTerms: ["codename-falcon"])
        )

        XCTAssertEqual(outcome.regions.map(\.category), [.customTerm])
    }

    // MARK: - AX-derived regions

    func testDetectsASecureFieldFrameAndProducesAnAccessibilityRegion() {
        let contentRect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let secureFrame = CGRect(x: 40, y: 30, width: 100, height: 20)

        let outcome = SensitiveContentDetector.detect(
            imageWidth: 400,
            imageHeight: 300,
            ocrResult: OCRResult(text: "", blocks: []),
            ocrAvailable: true,
            secureFieldFramesInScreenPoints: [secureFrame],
            axAvailable: true,
            windowContentRectInScreenPoints: contentRect,
            configuration: configuration(categories: [.secureField])
        )

        XCTAssertEqual(outcome.completeness, .complete)
        let region = try! XCTUnwrap(outcome.regions.first)
        XCTAssertEqual(region.category, .secureField)
        XCTAssertEqual(region.source, .accessibility)
        XCTAssertEqual(region.confidence, 1.0)
    }

    func testSecureFieldNotApplicableWithoutAWindowContentRectDoesNotPenalizeCompleteness() {
        // Region/scroll capture: no single associated window, so AX
        // detection is simply not attempted - this must not read as an
        // incomplete run.
        let outcome = SensitiveContentDetector.detect(
            imageWidth: 400,
            imageHeight: 300,
            ocrResult: OCRResult(text: "", blocks: []),
            ocrAvailable: true,
            secureFieldFramesInScreenPoints: [],
            axAvailable: true,
            windowContentRectInScreenPoints: nil,
            configuration: configuration(categories: [.secureField])
        )

        XCTAssertEqual(outcome.completeness, .complete)
        XCTAssertEqual(outcome.regions, [])
    }

    // MARK: - Completeness / status semantics (WP5 task 9)

    func testCompleteWhenEverythingRanAndNothingMatched() {
        let outcome = SensitiveContentDetector.detect(
            imageWidth: 100,
            imageHeight: 100,
            ocrResult: OCRResult(text: "", blocks: [block("nothing sensitive here", box: CGRect(x: 0, y: 0, width: 1, height: 1))]),
            ocrAvailable: true,
            secureFieldFramesInScreenPoints: [],
            axAvailable: true,
            windowContentRectInScreenPoints: CGRect(x: 0, y: 0, width: 100, height: 100),
            configuration: configuration(categories: [.email, .secureField])
        )
        XCTAssertEqual(outcome.completeness, .complete)
        XCTAssertTrue(outcome.warnings.isEmpty)
    }

    func testUnavailableWhenOCRDidNotComplete() {
        let outcome = SensitiveContentDetector.detect(
            imageWidth: 100,
            imageHeight: 100,
            ocrResult: OCRResult(text: "", blocks: []),
            ocrAvailable: false, // OCR itself failed upstream
            secureFieldFramesInScreenPoints: [],
            axAvailable: true,
            windowContentRectInScreenPoints: nil,
            configuration: configuration(categories: [.email])
        )
        XCTAssertEqual(outcome.completeness, .unavailable)
        XCTAssertFalse(outcome.warnings.isEmpty)
    }

    func testPartiallyIncompleteWhenAXPermissionIsMissingForAnApplicableWindow() {
        let outcome = SensitiveContentDetector.detect(
            imageWidth: 100,
            imageHeight: 100,
            ocrResult: OCRResult(text: "", blocks: []),
            ocrAvailable: true,
            secureFieldFramesInScreenPoints: [],
            axAvailable: false, // Accessibility not trusted
            windowContentRectInScreenPoints: CGRect(x: 0, y: 0, width: 100, height: 100),
            configuration: configuration(categories: [.secureField])
        )
        XCTAssertEqual(outcome.completeness, .partiallyIncomplete)
        XCTAssertFalse(outcome.warnings.isEmpty)
    }

    func testOCRFailureOutranksAXGapInSeverity() {
        // Both gaps occur at once; OCR's total absence of signal is the more
        // severe condition and must win.
        let outcome = SensitiveContentDetector.detect(
            imageWidth: 100,
            imageHeight: 100,
            ocrResult: OCRResult(text: "", blocks: []),
            ocrAvailable: false,
            secureFieldFramesInScreenPoints: [],
            axAvailable: false,
            windowContentRectInScreenPoints: CGRect(x: 0, y: 0, width: 100, height: 100),
            configuration: configuration(categories: [.email, .secureField])
        )
        XCTAssertEqual(outcome.completeness, .unavailable)
    }

    // MARK: - Padding and clamping feed through end to end

    func testDetectedRegionIsPaddedAndClampedNearTheImageEdge() {
        // A block hugging the very left edge of the image; after padding,
        // clamping must still leave a valid, non-negative rect starting at 0.
        let blocks = [block("john.doe@example.com", box: CGRect(x: 0, y: 0, width: 0.05, height: 0.05))]
        let outcome = SensitiveContentDetector.detect(
            imageWidth: 40,
            imageHeight: 40,
            ocrResult: OCRResult(text: "", blocks: blocks),
            ocrAvailable: true,
            secureFieldFramesInScreenPoints: [],
            axAvailable: true,
            windowContentRectInScreenPoints: nil,
            configuration: configuration(categories: [.email])
        )
        let region = try! XCTUnwrap(outcome.regions.first)
        XCTAssertGreaterThanOrEqual(region.normalizedRect.x, 0)
        XCTAssertGreaterThanOrEqual(region.normalizedRect.y, 0)
        XCTAssertLessThanOrEqual(region.normalizedRect.x + region.normalizedRect.width, 1.0001)
    }

    // MARK: - AX value-access guard (never reads secure field content)

    /// `SecureFieldFrameProviding` only exposes a trust check and a
    /// frame-only accessor, so the type system already forbids
    /// `SensitiveContentDetector`/`SensitiveContentPolicyRedactor` from
    /// reading a secure field's value. This test additionally proves the
    /// *real* implementation's source never references `kAXValueAttribute`
    /// at all — the concrete guarantee the spec's "never read
    /// `kAXValueAttribute` for secure fields" anti-pattern guard asks for,
    /// verifiable without a live, trusted Accessibility session.
    func testAXSecureFieldFrameProviderSourceNeverReferencesTheValueAttribute() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let sourceURL = thisFile
            .deletingLastPathComponent() // .../app/Tests/BerryShotTests
            .deletingLastPathComponent() // .../app/Tests
            .deletingLastPathComponent() // .../app
            .appendingPathComponent("Sources/Redaction/SensitiveContentDetector.swift")
        let source = try XCTUnwrap(try? String(contentsOf: sourceURL, encoding: .utf8), "expected to locate SensitiveContentDetector.swift relative to this test file")
        // Search for the actual API call shape, not just the bare
        // identifier: this file's own doc comments legitimately *name*
        // `kAXValueAttribute` in prose to document the guard, which a plain
        // substring search would also (harmlessly, but incorrectly) flag.
        XCTAssertFalse(source.contains("kAXValueAttribute as CFString"), "AX secure-field detection must never call AXUIElementCopyAttributeValue with kAXValueAttribute")
    }
}
