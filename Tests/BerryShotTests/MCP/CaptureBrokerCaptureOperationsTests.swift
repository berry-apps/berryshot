import XCTest
import CryptoKit
@testable import BerryShot
import BerryShotIPC

private actor CallRecorder {
    var ocrCallCount = 0
    var lastRedactionStyle: RedactionStyle?
    var lastRedactionPolicy: RedactionPolicy?

    func recordOCRCall() { ocrCallCount += 1 }
    func record(style: RedactionStyle, policy: RedactionPolicy) {
        lastRedactionStyle = style
        lastRedactionPolicy = policy
    }
}

private struct FixtureCaptureError: Error {}

private struct FakeWindowCapturing: CaptureBrokerWindowCapturing {
    var image: CGImage
    var contentRect = CGRectDTO(x: 0, y: 0, width: 400, height: 300)
    var pointPixelScale: Double = 2.0
    var errorToThrow: CaptureError?

    func captureWindow(_ descriptor: WindowDescriptor) async throws -> RawCapturedWindow {
        if let errorToThrow { throw errorToThrow }
        return RawCapturedWindow(image: image, descriptor: descriptor, pointPixelScale: pointPixelScale, contentRectInPoints: contentRect)
    }
}

private struct FakeOCR: CaptureOCRExtracting {
    let recorder: CallRecorder
    var result = OCRResult(text: "recognized text", blocks: [])
    var shouldThrow = false

    func extractText(from image: CGImage) async throws -> String {
        try await recognize(from: image).text
    }

    func recognize(from image: CGImage) async throws -> OCRResult {
        await recorder.recordOCRCall()
        if shouldThrow { throw FixtureCaptureError() }
        return result
    }
}

private struct FakeRedacting: CaptureBrokerRedacting {
    let recorder: CallRecorder
    var status: RedactionStatus = .applied
    var regionCount: Int = 1
    var warnings: [String] = []
    var errorToThrow: Error?

    func redact(_ image: CGImage, context: CaptureContext, ocrResult: OCRResult, ocrStatus: OCRStatus, style: RedactionStyle) async throws -> RedactedCaptureImage {
        await recorder.record(style: style, policy: context.redactionPolicy)
        if let errorToThrow { throw errorToThrow }
        return RedactedCaptureImage(image: image, status: status, warnings: warnings, regionCount: regionCount)
    }
}

final class CaptureBrokerCaptureOperationsTests: XCTestCase {
    private var rootDirectory: URL!

    override func setUp() {
        super.setUp()
        rootDirectory = URL(fileURLWithPath: "/tmp/bscapops-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: rootDirectory)
        rootDirectory = nil
        super.tearDown()
    }

    private func makeImage(width: Int = 10, height: Int = 10) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makeWindow(id: UInt32 = 7, bundleIdentifier: String = "com.example.App") -> WindowDescriptor {
        WindowDescriptor(
            id: id, bundleIdentifier: bundleIdentifier, applicationName: "Example", processID: 100,
            title: "Window", frameInScreenPoints: CGRectDTO(x: 0, y: 0, width: 400, height: 300), isOnScreen: true
        )
    }

    private func makeOperations(
        image: CGImage? = nil,
        captureError: CaptureError? = nil,
        redactionError: Error? = nil,
        redactionStatus: RedactionStatus = .applied,
        regionCount: Int = 1,
        recorder: CallRecorder = CallRecorder(),
        ocr: FakeOCR? = nil
    ) -> (ops: LiveCaptureBrokerCaptureOperations, store: CaptureArtifactStore, recorder: CallRecorder) {
        let store = CaptureArtifactStore(rootDirectory: rootDirectory)
        let capturing = FakeWindowCapturing(image: image ?? makeImage(), errorToThrow: captureError)
        let redacting = FakeRedacting(recorder: recorder, status: redactionStatus, regionCount: regionCount, errorToThrow: redactionError)
        let effectiveOCR = ocr ?? FakeOCR(recorder: recorder)
        let ops = LiveCaptureBrokerCaptureOperations(store: store, capturing: capturing, ocr: effectiveOCR, redacting: redacting)
        return (ops, store, recorder)
    }

    // MARK: - OCR skip / run

    func testOCRIsSkippedWhenPolicyIsNoneAndOCRNotRequested() async throws {
        let (ops, _, recorder) = makeOperations()
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        _ = try await ops.captureWindow(request, matchedWindow: makeWindow())
        let count = await recorder.ocrCallCount
        XCTAssertEqual(count, 0, "policy .none with ocr:false must never run Vision (07-performance-budget.md fast path)")
    }

    func testOCRRunsWhenPolicyRequiresRedactionEvenIfOCRFlagIsFalse() async throws {
        let (ops, _, recorder) = makeOperations()
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .required, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        _ = try await ops.captureWindow(request, matchedWindow: makeWindow())
        let count = await recorder.ocrCallCount
        XCTAssertEqual(count, 1)
    }

    func testOCRRunsWhenExplicitlyRequestedEvenWithPolicyNone() async throws {
        let (ops, _, recorder) = makeOperations()
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .none, redactionStyle: .solid, ocr: true, previewMaxEdge: 960)
        _ = try await ops.captureWindow(request, matchedWindow: makeWindow())
        let count = await recorder.ocrCallCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - OCR publication is opt-in

    func testOCRTextIsPublishedOnlyWhenRequestedEvenIfItRanInternally() async throws {
        let (ops, _, _) = makeOperations()
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .required, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        let manifest = try await ops.captureWindow(request, matchedWindow: makeWindow())
        XCTAssertFalse(manifest.ocrAvailable, "OCR ran internally for redaction detection, but publication was not requested")
        XCTAssertNil(manifest.ocrURI)
    }

    func testOCRTextIsPublishedWhenRequested() async throws {
        let (ops, _, _) = makeOperations()
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .required, redactionStyle: .solid, ocr: true, previewMaxEdge: 960)
        let manifest = try await ops.captureWindow(request, matchedWindow: makeWindow())
        XCTAssertTrue(manifest.ocrAvailable)
        XCTAssertNotNil(manifest.ocrURI)
    }

    // MARK: - Style forwarding

    func testRequestedRedactionStyleIsForwardedToTheRedactorExactly() async throws {
        let (ops, _, recorder) = makeOperations()
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .suggest, redactionStyle: .pixelate, ocr: false, previewMaxEdge: 960)
        _ = try await ops.captureWindow(request, matchedWindow: makeWindow())
        let style = await recorder.lastRedactionStyle
        let policy = await recorder.lastRedactionPolicy
        XCTAssertEqual(style, .pixelate)
        XCTAssertEqual(policy, .suggest)
    }

    // MARK: - Manifest / hash correspondence

    func testManifestFieldsMatchTheStoredFinalImage() async throws {
        let image = makeImage(width: 12, height: 8)
        let (ops, store, _) = makeOperations(image: image, redactionStatus: .applied, regionCount: 3)
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .suggest, redactionStyle: .blur, ocr: false, previewMaxEdge: 960)
        let manifest = try await ops.captureWindow(request, matchedWindow: makeWindow())

        XCTAssertEqual(manifest.redactionStatus, .applied)
        XCTAssertEqual(manifest.redactionRegionCount, 3)
        XCTAssertEqual(manifest.windowID, 7)
        XCTAssertEqual(manifest.bundleIdentifier, "com.example.App")
        XCTAssertEqual(manifest.pixelWidth, image.width)
        XCTAssertEqual(manifest.pixelHeight, image.height)
        XCTAssertEqual(manifest.pointPixelScale, 2.0)

        // The manifest's sha256 must describe exactly the bytes on disk —
        // "the hash describes the final redacted full artifact"
        // (05-mcp-server-contract.md section 5).
        let location = try await store.resolve(captureID: manifest.captureID, kind: .image)
        let diskData = try Data(contentsOf: URL(fileURLWithPath: location.path))
        let recomputed = SHA256.hash(data: diskData).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(manifest.sha256, recomputed)
    }

    // MARK: - Error mapping

    func testWindowNotAvailableMapsToWindowNotAvailableCode() async throws {
        let (ops, _, _) = makeOperations(captureError: .windowNotAvailable(windowID: 7))
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        do {
            _ = try await ops.captureWindow(request, matchedWindow: makeWindow())
            XCTFail("Expected window_not_available")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .windowNotAvailable)
        }
    }

    func testWindowIdentityChangedMapsToWindowIdentityChangedCode() async throws {
        let (ops, _, _) = makeOperations(captureError: .windowIdentityChanged(windowID: 7, expectedBundleIdentifier: "com.example.App", actualBundleIdentifier: "com.example.Other"))
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        do {
            _ = try await ops.captureWindow(request, matchedWindow: makeWindow())
            XCTFail("Expected window_identity_changed")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .windowIdentityChanged)
        }
    }

    func testPermissionDeniedMapsToPermissionDeniedCode() async throws {
        let (ops, _, _) = makeOperations(captureError: .permissionDenied)
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        do {
            _ = try await ops.captureWindow(request, matchedWindow: makeWindow())
            XCTFail("Expected permission_denied")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .permissionDenied)
        }
    }

    func testRedactionRequiredErrorMapsToRedactionReviewRequiredCode() async throws {
        let (ops, _, _) = makeOperations(redactionError: RedactionRequiredError.noReviewedRegion)
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .required, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        do {
            _ = try await ops.captureWindow(request, matchedWindow: makeWindow())
            XCTFail("Expected redaction_review_required")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .redactionReviewRequired)
        }
    }

    func testRedactionRendererErrorMapsToRedactionUnavailableCode() async throws {
        let (ops, _, _) = makeOperations(redactionError: RedactionRendererError.renderFailed)
        let request = CaptureWindowRequest(windowID: 7, expectedBundleIdentifier: "com.example.App", redactionPolicy: .required, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        do {
            _ = try await ops.captureWindow(request, matchedWindow: makeWindow())
            XCTFail("Expected redaction_unavailable")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .redactionUnavailable)
        }
    }
}
