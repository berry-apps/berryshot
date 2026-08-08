import Cocoa
import CoreGraphics
import CryptoKit
import XCTest
@testable import BerryShot

/// Integration-style tests proving `04-sensitive-redaction-spec.md` section 5's
/// mandatory persistence order end-to-end through the real
/// `CaptureArtifactProcessor` + `ManualRedactionPolicyRedactor`: OCR sees the
/// raw image, every sink after it sees only the flattened result, and
/// `required` fails closed before any sink runs at all.
@MainActor
final class RedactionOrderingTests: XCTestCase {
    func testNonePolicyLeavesExistingWorkflowUnchanged() async throws {
        let recorder = SinkRecorder()
        let processor = CaptureArtifactProcessor(
            ocr: EmptyOCR(),
            redactor: ManualRedactionPolicyRedactor(),
            imageStore: RecordingStore(recorder: recorder),
            uploadProvider: RecordingUploader(recorder: recorder),
            historySink: RecordingHistorySink(recorder: recorder)
        )
        let image = makeSolidImage(width: 10, height: 10, red: 0.1, green: 0.2, blue: 0.3)
        // Default `redactionPolicy` is `.none`, matching every pre-WP4 call site.
        let context = CaptureContext.window(windowID: 1, bundleIdentifier: "com.example.none")

        let artifact = try await processor.processFinalImage(image, context: context, action: .saveLocal)

        XCTAssertEqual(artifact.redactionStatus, .notRequested)
        XCTAssertEqual(artifact.redactionWarnings, [])
        let stored = await recorder.storedFingerprints
        XCTAssertEqual(stored, [fingerprint(image)], "policy .none must leave the existing no-redaction workflow byte-identical")
        await cleanup(recorder)
    }

    func testSuggestPolicyWithNoManualRegionsIsNeedsReviewAndDoesNotAlterPixels() async throws {
        let recorder = SinkRecorder()
        let processor = CaptureArtifactProcessor(
            ocr: EmptyOCR(),
            redactor: ManualRedactionPolicyRedactor(),
            imageStore: RecordingStore(recorder: recorder),
            uploadProvider: RecordingUploader(recorder: recorder),
            historySink: RecordingHistorySink(recorder: recorder)
        )
        let image = makeSolidImage(width: 10, height: 10, red: 0.4, green: 0.4, blue: 0.4)
        let context = CaptureContext.window(windowID: 2, bundleIdentifier: "com.example.suggest-empty", redactionPolicy: .suggest)

        let artifact = try await processor.processFinalImage(image, context: context, action: .saveLocal)

        XCTAssertEqual(artifact.redactionStatus, .needsReview)
        XCTAssertEqual(artifact.redactionWarnings, [automaticRedactionUnavailableWarning])
        let stored = await recorder.storedFingerprints
        XCTAssertEqual(stored, [fingerprint(image)], "an unreviewed capture must never silently claim redaction by altering pixels")
        await cleanup(recorder)
    }

    func testSuggestPolicyWithReviewedRegionFlattensBeforeEverySinkButAfterOCR() async throws {
        let recorder = SinkRecorder()
        let processor = CaptureArtifactProcessor(
            ocr: RecordingOCR(recorder: recorder),
            redactor: ManualRedactionPolicyRedactor(),
            imageStore: RecordingStore(recorder: recorder),
            uploadProvider: RecordingUploader(recorder: recorder),
            historySink: RecordingHistorySink(recorder: recorder)
        )
        let image = makeSolidImage(width: 20, height: 20, red: 1, green: 0, blue: 0)
        let region = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 1, height: 1), style: .solid)
        let context = CaptureContext.window(
            windowID: 3,
            bundleIdentifier: "com.example.suggest-applied",
            redactionPolicy: .suggest,
            manualRedactionRegions: [region]
        )

        let artifact = try await processor.processFinalImage(image, context: context, action: .upload)

        XCTAssertEqual(artifact.redactionStatus, .applied)
        // OCR must see the raw pixels (mandatory order: OCR/AX/manual
        // detection happens before the flattened image is produced).
        let ocrFingerprint = await recorder.ocrFingerprints.first
        XCTAssertEqual(ocrFingerprint, fingerprint(image))
        // Store/upload/history must all see the FLATTENED image, never raw.
        let storedFingerprint = await recorder.storedFingerprints.first
        XCTAssertNotEqual(storedFingerprint, fingerprint(image), "the stored image must be the flattened result, not the raw capture")
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.uploadCount, 1)
        XCTAssertEqual(snapshot.historyCount, 1)
        await cleanup(recorder)
    }

    func testRequiredPolicyWithReviewedRegionSucceedsAndPersistsTheFlattenedImage() async throws {
        let recorder = SinkRecorder()
        let processor = CaptureArtifactProcessor(
            ocr: EmptyOCR(),
            redactor: ManualRedactionPolicyRedactor(),
            imageStore: RecordingStore(recorder: recorder),
            uploadProvider: RecordingUploader(recorder: recorder),
            historySink: RecordingHistorySink(recorder: recorder)
        )
        let image = makeSolidImage(width: 12, height: 12, red: 0.05, green: 0.8, blue: 0.1)
        let region = RedactionRegion.manual(normalizedRect: CGRectDTO(x: 0, y: 0, width: 1, height: 1), style: .pixelate)
        let context = CaptureContext.window(
            windowID: 4,
            bundleIdentifier: "com.example.required-applied",
            redactionPolicy: .required,
            manualRedactionRegions: [region]
        )

        let artifact = try await processor.processFinalImage(image, context: context, action: .saveLocal)

        XCTAssertEqual(artifact.redactionStatus, .applied)
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.historyCount, 1)
        await cleanup(recorder)
    }

    func testRequiredPolicyWithNoReviewedRegionFailsClosedAndTouchesNoSink() async throws {
        let processor = CaptureArtifactProcessor(
            ocr: EmptyOCR(),
            redactor: ManualRedactionPolicyRedactor(),
            imageStore: UnreachableStore(),
            uploadProvider: UnreachableUploader(),
            historySink: UnreachableHistorySink()
        )
        let image = makeSolidImage(width: 8, height: 8, red: 0.5, green: 0.5, blue: 0.5)
        let context = CaptureContext.window(windowID: 5, bundleIdentifier: "com.example.required-empty", redactionPolicy: .required)

        do {
            _ = try await processor.processFinalImage(image, context: context, action: .saveLocal)
            XCTFail("required policy with no reviewed region must fail closed")
        } catch let error as RedactionRequiredError {
            XCTAssertEqual(error, .noReviewedRegion)
        }
        // `UnreachableStore`/`UnreachableUploader`/`UnreachableHistorySink`
        // call `XCTFail` if the processor ever reaches them, so reaching this
        // line without a failure already proves no sink ran.
    }

    func testCancellationDuringRedactionCreatesNoRawArtifact() async throws {
        let processor = CaptureArtifactProcessor(
            ocr: EmptyOCR(),
            redactor: CancellingRedactor(),
            imageStore: UnreachableStore(),
            uploadProvider: UnreachableUploader(),
            historySink: UnreachableHistorySink()
        )
        let image = makeSolidImage(width: 8, height: 8, red: 0.5, green: 0.5, blue: 0.5)
        let context = CaptureContext.window(windowID: 6, bundleIdentifier: "com.example.cancelled", redactionPolicy: .suggest)

        do {
            _ = try await processor.processFinalImage(image, context: context, action: .saveLocal)
            XCTFail("expected cancellation to propagate before any sink ran")
        } catch is CancellationError {
            // Expected.
        }
    }

    // MARK: - Fixtures

    private func makeSolidImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func cleanup(_ recorder: SinkRecorder) async {
        let files = await recorder.storedFiles
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

private func fingerprint(_ image: CGImage) -> String {
    guard let providerData = image.dataProvider?.data else { return "" }
    return SHA256.hash(data: providerData as Data).map { String(format: "%02x", $0) }.joined()
}

private actor SinkRecorder {
    struct Snapshot {
        let uploadCount: Int
        let historyCount: Int
    }

    private(set) var ocrFingerprints: [String] = []
    private(set) var storedFingerprints: [String] = []
    private(set) var storedFiles: [URL] = []
    private(set) var uploadHashes: [String] = []
    private(set) var historyCount = 0

    func snapshot() -> Snapshot {
        Snapshot(uploadCount: uploadHashes.count, historyCount: historyCount)
    }

    func recordOCR(_ fingerprint: String) {
        ocrFingerprints.append(fingerprint)
    }

    func recordStored(_ fingerprint: String, fileURL: URL) {
        storedFingerprints.append(fingerprint)
        storedFiles.append(fileURL)
    }

    func recordUpload(_ hash: String) {
        uploadHashes.append(hash)
    }

    func recordHistory() {
        historyCount += 1
    }
}

private struct EmptyOCR: CaptureOCRExtracting {
    func extractText(from _: CGImage) async throws -> String { "" }
}

private struct RecordingOCR: CaptureOCRExtracting {
    let recorder: SinkRecorder

    func extractText(from image: CGImage) async throws -> String {
        await recorder.recordOCR(fingerprint(image))
        return ""
    }
}

private struct CancellingRedactor: CaptureRedacting {
    func redact(_: CGImage, context _: CaptureContext) async throws -> RedactedCaptureImage {
        throw CancellationError()
    }
}

private actor RecordingStore: CaptureImageStoring {
    let recorder: SinkRecorder

    init(recorder: SinkRecorder) {
        self.recorder = recorder
    }

    func storePNG(_ image: CGImage) async throws -> URL {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BerryShot-RedactionOrderingTests-\(UUID().uuidString).png")
        try data.write(to: fileURL, options: .atomic)
        await recorder.recordStored(fingerprint(image), fileURL: fileURL)
        return fileURL
    }
}

private struct UnreachableStore: CaptureImageStoring {
    func storePNG(_: CGImage) async throws -> URL {
        XCTFail("Store must not run when redaction did not produce an approved image")
        return URL(fileURLWithPath: "/tmp/unreachable.png")
    }
}

private actor RecordingUploader: CaptureUploadProviding {
    let recorder: SinkRecorder

    init(recorder: SinkRecorder) {
        self.recorder = recorder
    }

    func upload(_ request: CaptureUploadRequest) async throws -> URL {
        await recorder.recordUpload(try XCTUnwrap(request.imageHash))
        return URL(string: "https://example.com/final.png")!
    }
}

private struct UnreachableUploader: CaptureUploadProviding {
    func upload(_ request: CaptureUploadRequest) async throws -> URL {
        XCTFail("Uploader must not run when redaction did not produce an approved image")
        return request.fileURL
    }
}

@MainActor
private final class RecordingHistorySink: CaptureHistorySinking {
    let recorder: SinkRecorder

    init(recorder: SinkRecorder) {
        self.recorder = recorder
    }

    func record(_: CaptureArtifact) async throws {
        try Task.checkCancellation()
        await recorder.recordHistory()
    }
}

@MainActor
private final class UnreachableHistorySink: CaptureHistorySinking {
    func record(_: CaptureArtifact) async throws {
        XCTFail("History must not run when redaction did not produce an approved image")
    }
}
