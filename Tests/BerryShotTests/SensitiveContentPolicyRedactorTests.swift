import CoreGraphics
import CryptoKit
import XCTest
@testable import BerryShot

/// End-to-end tests for `SensitiveContentPolicyRedactor`: the `CaptureRedacting`
/// conformer `CaptureCoordinator` wires into the main pipeline. Covers status
/// semantics (WP5 task 9), the AX secure-field non-access proof at the
/// redactor boundary, and golden masking of fake test secrets.
final class SensitiveContentPolicyRedactorTests: XCTestCase {
    private func makeSolidImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func pixel(_ image: CGImage, row: Int, col: Int) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        let bytesPerRow = image.bytesPerRow
        let offset = row * bytesPerRow + col * 4
        return [data[offset], data[offset + 1], data[offset + 2]]
    }

    private func configurationProvider(_ configuration: SensitiveDetectionConfiguration) -> @Sendable () async -> SensitiveDetectionConfiguration {
        { configuration }
    }

    private func configuration(
        categories: Set<SensitiveCategory>,
        customTerms: [String] = [],
        style: RedactionStyle = .solid
    ) -> SensitiveDetectionConfiguration {
        SensitiveDetectionConfiguration(enabledCategories: categories, customTerms: customTerms, customTermsCaseSensitive: false, style: style)
    }

    // MARK: - Status semantics

    func testSuggestWithNothingDetectedAndFullCompletionIsClean() async throws {
        let redactor = SensitiveContentPolicyRedactor(
            secureFieldProvider: FakeSecureFieldProvider(trusted: true, framesByProcessID: [:]),
            configurationProvider: configurationProvider(configuration(categories: [.email]))
        )
        let image = makeSolidImage(width: 20, height: 20, red: 0.2, green: 0.3, blue: 0.4)
        let context = CaptureContext.window(windowID: 1, bundleIdentifier: "com.example.clean", redactionPolicy: .suggest)

        let result = try await redactor.redact(image, context: context, ocrResult: OCRResult(text: "", blocks: []), ocrStatus: .extracted)

        XCTAssertEqual(result.status, .clean)
        XCTAssertEqual(fingerprint(result.image), fingerprint(image), "clean must not alter pixels")
    }

    func testSuggestWithOCRUnavailableIsUnavailableNotClean() async throws {
        let redactor = SensitiveContentPolicyRedactor(
            secureFieldProvider: FakeSecureFieldProvider(trusted: true, framesByProcessID: [:]),
            configurationProvider: configurationProvider(configuration(categories: [.email]))
        )
        let image = makeSolidImage(width: 20, height: 20, red: 0.2, green: 0.3, blue: 0.4)
        let context = CaptureContext.window(windowID: 2, bundleIdentifier: "com.example.unavailable", redactionPolicy: .suggest)

        let result = try await redactor.redact(image, context: context, ocrResult: OCRResult(text: "", blocks: []), ocrStatus: .unavailable)

        XCTAssertEqual(result.status, .unavailable)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testSuggestWithAXGapOnAWindowCaptureIsNeedsReview() async throws {
        let redactor = SensitiveContentPolicyRedactor(
            secureFieldProvider: FakeSecureFieldProvider(trusted: false, framesByProcessID: [:]),
            configurationProvider: configurationProvider(configuration(categories: [.secureField]))
        )
        let image = makeSolidImage(width: 20, height: 20, red: 0.2, green: 0.3, blue: 0.4)
        let context = CaptureContext.window(
            windowID: 3,
            bundleIdentifier: "com.example.ax-gap",
            processID: 4242,
            windowContentRectInScreenPoints: CGRectDTO(x: 0, y: 0, width: 20, height: 20),
            redactionPolicy: .suggest
        )

        let result = try await redactor.redact(image, context: context, ocrResult: OCRResult(text: "", blocks: []), ocrStatus: .extracted)

        XCTAssertEqual(result.status, .needsReview)
    }

    func testRequiredWithFullCompletionAndNothingDetectedReturnsCleanRatherThanFailingClosed() async throws {
        // WP5 changes WP4's unconditional fail-closed-on-empty-regions
        // behavior: once real detection exists, "required + detection ran
        // fully + found nothing" is a legitimately safe, unmodified image.
        let redactor = SensitiveContentPolicyRedactor(
            secureFieldProvider: FakeSecureFieldProvider(trusted: true, framesByProcessID: [:]),
            configurationProvider: configurationProvider(configuration(categories: [.email]))
        )
        let image = makeSolidImage(width: 20, height: 20, red: 0.5, green: 0.5, blue: 0.5)
        let context = CaptureContext.window(windowID: 5, bundleIdentifier: "com.example.required-clean", redactionPolicy: .required)

        let result = try await redactor.redact(image, context: context, ocrResult: OCRResult(text: "", blocks: []), ocrStatus: .extracted)

        XCTAssertEqual(result.status, .clean)
    }

    func testRequiredFailsClosedWhenDetectionDidNotComplete() async throws {
        let redactor = SensitiveContentPolicyRedactor(
            secureFieldProvider: FakeSecureFieldProvider(trusted: true, framesByProcessID: [:]),
            configurationProvider: configurationProvider(configuration(categories: [.email]))
        )
        let image = makeSolidImage(width: 20, height: 20, red: 0.5, green: 0.5, blue: 0.5)
        let context = CaptureContext.window(windowID: 6, bundleIdentifier: "com.example.required-fail", redactionPolicy: .required)

        do {
            _ = try await redactor.redact(image, context: context, ocrResult: OCRResult(text: "", blocks: []), ocrStatus: .unavailable)
            XCTFail("required policy must fail closed when detection did not complete")
        } catch let error as RedactionRequiredError {
            XCTAssertEqual(error, .noReviewedRegion)
        }
    }

    func testNonePolicyNeverRunsDetectionAndLeavesPixelsUntouched() async throws {
        let provider = FakeSecureFieldProvider(trusted: true, framesByProcessID: [4242: [CGRect(x: 0, y: 0, width: 5, height: 5)]])
        let redactor = SensitiveContentPolicyRedactor(
            secureFieldProvider: provider,
            configurationProvider: configurationProvider(configuration(categories: [.secureField]))
        )
        let image = makeSolidImage(width: 20, height: 20, red: 0.5, green: 0.5, blue: 0.5)
        let context = CaptureContext.window(
            windowID: 7,
            bundleIdentifier: "com.example.none",
            processID: 4242,
            windowContentRectInScreenPoints: CGRectDTO(x: 0, y: 0, width: 20, height: 20),
            redactionPolicy: .none
        )

        let result = try await redactor.redact(image, context: context, ocrResult: OCRResult(text: "", blocks: []), ocrStatus: .extracted)

        XCTAssertEqual(result.status, .notRequested)
        XCTAssertEqual(fingerprint(result.image), fingerprint(image))
        let frameCalls = provider.frameCallCount
        XCTAssertEqual(frameCalls, 0, "`.none` must never invoke AX scanning at all")
    }

    // MARK: - AX non-access proof at the redactor boundary

    func testSecureFieldFramesAreNeverRequestedWhenAccessibilityIsNotTrusted() async throws {
        let provider = FakeSecureFieldProvider(trusted: false, framesByProcessID: [4242: [CGRect(x: 0, y: 0, width: 5, height: 5)]])
        let redactor = SensitiveContentPolicyRedactor(
            secureFieldProvider: provider,
            configurationProvider: configurationProvider(configuration(categories: [.secureField]))
        )
        let image = makeSolidImage(width: 20, height: 20, red: 0.5, green: 0.5, blue: 0.5)
        let context = CaptureContext.window(
            windowID: 8,
            bundleIdentifier: "com.example.untrusted",
            processID: 4242,
            windowContentRectInScreenPoints: CGRectDTO(x: 0, y: 0, width: 20, height: 20),
            redactionPolicy: .suggest
        )

        _ = try await redactor.redact(image, context: context, ocrResult: OCRResult(text: "", blocks: []), ocrStatus: .extracted)

        let frameCalls = provider.frameCallCount
        XCTAssertEqual(frameCalls, 0, "must never call the frame-scanning API when Accessibility is not trusted")
    }

    func testSecureFieldScanIsTargetedAtTheCapturedProcessID() async throws {
        let provider = FakeSecureFieldProvider(trusted: true, framesByProcessID: [4242: [CGRect(x: 5, y: 5, width: 5, height: 5)]])
        let redactor = SensitiveContentPolicyRedactor(
            secureFieldProvider: provider,
            configurationProvider: configurationProvider(configuration(categories: [.secureField]))
        )
        let image = makeSolidImage(width: 20, height: 20, red: 0.5, green: 0.5, blue: 0.5)
        let context = CaptureContext.window(
            windowID: 9,
            bundleIdentifier: "com.example.targeted",
            processID: 4242,
            windowContentRectInScreenPoints: CGRectDTO(x: 0, y: 0, width: 20, height: 20),
            redactionPolicy: .suggest
        )

        let result = try await redactor.redact(image, context: context, ocrResult: OCRResult(text: "", blocks: []), ocrStatus: .extracted)

        XCTAssertEqual(result.status, .applied)
        let requestedPIDs = provider.requestedProcessIDs
        XCTAssertEqual(requestedPIDs, [4242])
    }

    // MARK: - Golden masking image

    func testDetectedRegionIsFlattenedAndOnlyThatAreaChanges() async throws {
        let width = 40, height = 40
        let image = makeSolidImage(width: width, height: height, red: 0.9, green: 0.1, blue: 0.1)
        // A fake "secret" line placed in the top-left quadrant of the image
        // (Vision box: minX 0, maxX 0.4, minY 0.6, maxY 1.0 -> top-left in
        // top-left/y-down pixel space).
        let block = RecognizedTextBlock(
            text: "john.doe@example.com",
            confidence: 0.9,
            normalizedBoundingBox: CGRectDTO(x: 0, y: 0.6, width: 0.4, height: 0.4)
        )
        let redactor = SensitiveContentPolicyRedactor(
            secureFieldProvider: FakeSecureFieldProvider(trusted: true, framesByProcessID: [:]),
            configurationProvider: configurationProvider(configuration(categories: [.email], style: .solid))
        )
        let context = CaptureContext.window(windowID: 10, bundleIdentifier: "com.example.golden", redactionPolicy: .suggest)

        let result = try await redactor.redact(
            image, context: context, ocrResult: OCRResult(text: block.text, blocks: [block]), ocrStatus: .extracted
        )

        XCTAssertEqual(result.status, .applied)
        // Inside the masked top-left region: changed from the original red fill.
        XCTAssertNotEqual(pixel(result.image, row: 2, col: 2), pixel(image, row: 2, col: 2))
        // Far outside the masked region (bottom-right corner): bit-exact.
        XCTAssertEqual(pixel(result.image, row: height - 1, col: width - 1), pixel(image, row: height - 1, col: width - 1))
    }

    func testManualAndAutomaticRegionsBothFlattenInOnePass() async throws {
        let width = 40, height = 40
        let image = makeSolidImage(width: width, height: height, red: 0.1, green: 0.8, blue: 0.1)
        let block = RecognizedTextBlock(
            text: "4111 1111 1111 1111",
            confidence: 0.9,
            normalizedBoundingBox: CGRectDTO(x: 0, y: 0.7, width: 0.3, height: 0.3) // top-left area
        )
        let manualRegion = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0.7, y: 0.7, width: 0.3, height: 0.3), style: .solid) // bottom-right area
        let redactor = SensitiveContentPolicyRedactor(
            secureFieldProvider: FakeSecureFieldProvider(trusted: true, framesByProcessID: [:]),
            configurationProvider: configurationProvider(configuration(categories: [.creditCard], style: .solid))
        )
        let context = CaptureContext.window(
            windowID: 11,
            bundleIdentifier: "com.example.mixed",
            redactionPolicy: .suggest,
            manualRedactionRegions: [manualRegion]
        )

        let result = try await redactor.redact(
            image, context: context, ocrResult: OCRResult(text: block.text, blocks: [block]), ocrStatus: .extracted
        )

        XCTAssertEqual(result.status, .applied)
        // Top-left (automatic card match) changed.
        XCTAssertNotEqual(pixel(result.image, row: 2, col: 2), pixel(image, row: 2, col: 2))
        // Bottom-right (manual region) changed.
        XCTAssertNotEqual(pixel(result.image, row: height - 2, col: width - 2), pixel(image, row: height - 2, col: width - 2))
        // Center (untouched by either) is bit-exact.
        XCTAssertEqual(pixel(result.image, row: height / 2, col: width / 2), pixel(image, row: height / 2, col: width / 2))
    }

    private func fingerprint(_ image: CGImage) -> String {
        guard let providerData = image.dataProvider?.data else { return "" }
        return SHA256.hash(data: providerData as Data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Test double that never touches real AX APIs. `frameCallCount`/
/// `requestedProcessIDs` let tests prove the redactor never asks for frames
/// while untrusted, and asks only for the captured window's own process.
/// `SecureFieldFrameProviding.secureFieldFrames(processID:)` is a
/// synchronous protocol requirement (matching the real AX implementation,
/// which never suspends), so this is a plain lock-protected class rather
/// than an actor.
private final class FakeSecureFieldProvider: SecureFieldFrameProviding, @unchecked Sendable {
    let isAccessibilityTrusted: Bool
    private let framesByProcessID: [Int32: [CGRect]]
    private let lock = NSLock()
    private var _frameCallCount = 0
    private var _requestedProcessIDs: [Int32] = []

    init(trusted: Bool, framesByProcessID: [Int32: [CGRect]]) {
        self.isAccessibilityTrusted = trusted
        self.framesByProcessID = framesByProcessID
    }

    var frameCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _frameCallCount
    }

    var requestedProcessIDs: [Int32] {
        lock.lock(); defer { lock.unlock() }
        return _requestedProcessIDs
    }

    func secureFieldFrames(processID: Int32) -> [CGRect] {
        lock.lock()
        _frameCallCount += 1
        _requestedProcessIDs.append(processID)
        lock.unlock()
        return framesByProcessID[processID] ?? []
    }
}
