import Cocoa
import CoreGraphics
import CryptoKit
import XCTest
@testable import BerryShot

@MainActor
final class CaptureArtifactProcessorTests: XCTestCase {
    func testEachSourceRoutesExactlyOneFinalImageAndOnlyRegionIsCropped() async throws {
        let spy = FinalImageProcessorSpy()
        let router = CaptureArtifactProcessingRouter(finalImageProcessor: spy)
        let image = makeImage(width: 4, height: 4)

        _ = try await router.processRegionDisplayCapture(
            image,
            region: CGRect(x: 1, y: 1, width: 2, height: 2),
            scale: 1,
            context: .region(displayID: 1, rect: CGRect(x: 1, y: 1, width: 2, height: 2)),
            action: .saveLocal
        )
        _ = try await router.processFinalImage(
            image,
            context: .window(windowID: 2, bundleIdentifier: "com.example.window"),
            action: .saveLocal
        )
        _ = try await router.processFinalImage(
            image,
            context: .applicationWindow(windowID: 3, bundleIdentifier: "com.example.application"),
            action: .saveLocal
        )
        _ = try await router.processFinalImage(image, context: .scrollResult(), action: .saveLocal)

        let invocations = await spy.allInvocations()
        XCTAssertEqual(invocations.count, 4)
        XCTAssertEqual(invocations.map(\.context.source), [.region, .window, .applicationWindow, .scrollResult])
        XCTAssertEqual(invocations[0].width, 2)
        XCTAssertEqual(invocations[0].height, 2)

        // Window, application-window, and scroll captures are already final and
        // therefore reach the final processor at their original dimensions.
        for invocation in invocations.dropFirst() {
            XCTAssertEqual(invocation.width, 4)
            XCTAssertEqual(invocation.height, 4)
        }
    }

    func testStoredFileHashIsPassedToUploadAndHistory() async throws {
        let recorder = HashRecorder()
        let processor = CaptureArtifactProcessor(
            ocr: RecordingOCR(recorder: recorder),
            redactor: NoOpCaptureRedactor(),
            imageStore: RecordingStore(recorder: recorder),
            uploadProvider: RecordingUploader(recorder: recorder),
            historySink: RecordingHistorySink(recorder: recorder)
        )
        let image = makeImage(width: 3, height: 2)

        let artifact = try await processor.processFinalImage(
            image,
            context: .window(windowID: 42, bundleIdentifier: "com.example.target"),
            action: .upload
        )
        let storedFiles = await recorder.storedFiles
        defer { storedFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

        let expectedHash = try XCTUnwrap(artifact.imageHash)
        XCTAssertEqual(artifact.redactionStatus, .notRequested)
        XCTAssertEqual(expectedHash, try XCTUnwrap(CaptureImageHasher.hash(fileAt: artifact.storedURL)))
        // OCR reads the raw final image before it is encoded. With WP1's no-op
        // redactor, its pixel fingerprint must be the exact image that is
        // subsequently encoded; upload and history then receive the persisted
        // file hash of that same final image.
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.ocrImageFingerprints, snapshot.storedImageFingerprints)
        XCTAssertEqual(snapshot.uploadHashes, [expectedHash])
        XCTAssertEqual(snapshot.historyHashes, [expectedHash])
        XCTAssertEqual(snapshot.historyCount, 1)
    }

    func testDisplayCropPreservesExactLegacyScaledGeometry() throws {
        let image = makePatternImage(width: 8, height: 8)
        let region = CGRect(x: 1.25, y: 0.5, width: 3.25, height: 2.5)
        let scale: CGFloat = 1.5
        let legacyRect = CGRect(
            x: region.minX * scale,
            y: region.minY * scale,
            width: region.width * scale,
            height: region.height * scale
        )

        let expected = try XCTUnwrap(image.cropping(to: legacyRect))
        let actual = try cropDisplayCapture(image, region: region, scale: scale)

        XCTAssertEqual(imageFingerprint(actual), imageFingerprint(expected))
    }

    func testStoreFailureIsTypedAndDoesNotCreateHistoryEntry() async throws {
        let history = RecordingHistorySink(recorder: HashRecorder())
        let processor = CaptureArtifactProcessor(
            ocr: EmptyOCR(),
            redactor: NoOpCaptureRedactor(),
            imageStore: FailingStore(),
            uploadProvider: UnreachableUploader(),
            historySink: history
        )

        do {
            _ = try await processor.processFinalImage(
                makeImage(width: 2, height: 2),
                context: .scrollResult(),
                action: .saveLocal
            )
            XCTFail("Expected a typed store failure")
        } catch let error as CaptureArtifactProcessorError {
            guard case .imageStoreFailed = error else {
                return XCTFail("Unexpected typed error: \(error)")
            }
        }

        let historySnapshot = await history.recorder.snapshot()
        XCTAssertEqual(historySnapshot.historyCount, 0)
    }

    func testUploaderCancellationPropagatesAndDoesNotCreateHistoryEntry() async throws {
        let recorder = HashRecorder()
        let history = RecordingHistorySink(recorder: recorder)
        let processor = CaptureArtifactProcessor(
            ocr: EmptyOCR(),
            redactor: NoOpCaptureRedactor(),
            imageStore: RecordingStore(recorder: recorder),
            uploadProvider: CancellingUploader(),
            historySink: history
        )

        do {
            _ = try await processor.processFinalImage(
                makeImage(width: 2, height: 2),
                context: .window(windowID: 8, bundleIdentifier: "com.example.upload-cancelled"),
                action: .upload
            )
            XCTFail("Expected uploader cancellation to be propagated")
        } catch is CancellationError {
            // Expected: a cancelled uploader must not become local fallback.
        }
        let storedFiles = await recorder.storedFiles
        defer { storedFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

        let historySnapshot = await history.recorder.snapshot()
        XCTAssertEqual(historySnapshot.historyCount, 0)
    }

    func testOCRCancellationPropagatesAndDoesNotCreateHistoryEntry() async throws {
        let recorder = HashRecorder()
        let history = RecordingHistorySink(recorder: recorder)
        let processor = CaptureArtifactProcessor(
            ocr: CancellingOCR(),
            redactor: UnreachableRedactor(),
            imageStore: UnreachableStore(),
            uploadProvider: UnreachableUploader(),
            historySink: history
        )

        do {
            _ = try await processor.processFinalImage(
                makeImage(width: 2, height: 2),
                context: .window(windowID: 9, bundleIdentifier: "com.example.ocr-cancelled"),
                action: .saveLocal
            )
            XCTFail("Expected OCR cancellation to be propagated")
        } catch is CancellationError {
            // Expected: cancellation is not an OCR availability failure.
        }

        let historySnapshot = await recorder.snapshot()
        XCTAssertEqual(historySnapshot.historyCount, 0)
    }

    func testCancellationWhileHistoryHopIsQueuedDoesNotWriteHistory() async throws {
        let recorder = HashRecorder()
        let historyGate = HistoryRecordingGate()
        let history = QueuedHistorySink(recorder: recorder, gate: historyGate)
        let processor = CaptureArtifactProcessor(
            ocr: EmptyOCR(),
            redactor: NoOpCaptureRedactor(),
            imageStore: RecordingStore(recorder: recorder),
            uploadProvider: RecordingUploader(recorder: recorder),
            historySink: history
        )

        let task = Task {
            try await processor.processFinalImage(
                self.makeImage(width: 2, height: 2),
                context: .window(windowID: 10, bundleIdentifier: "com.example.history-hop-cancelled"),
                action: .upload
            )
        }

        await historyGate.waitUntilEntered()
        task.cancel()
        await historyGate.release()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation during the queued history hop")
        } catch is CancellationError {
            // Expected: the sink observes cancellation before its durable write.
        }

        let storedFiles = await recorder.storedFiles
        defer { storedFiles.forEach { try? FileManager.default.removeItem(at: $0) } }
        let historySnapshot = await recorder.snapshot()
        XCTAssertEqual(historySnapshot.historyCount, 0)
    }

    func testCancellationDoesNotCreateHistoryEntry() async throws {
        let history = RecordingHistorySink(recorder: HashRecorder())
        let processor = CaptureArtifactProcessor(
            ocr: EmptyOCR(),
            redactor: CancellingRedactor(),
            imageStore: UnreachableStore(),
            uploadProvider: UnreachableUploader(),
            historySink: history
        )

        do {
            _ = try await processor.processFinalImage(
                makeImage(width: 2, height: 2),
                context: .window(windowID: 7, bundleIdentifier: "com.example.cancelled"),
                action: .saveLocal
            )
            XCTFail("Expected cancellation to be propagated")
        } catch is CancellationError {
            // Expected: a cancelled pipeline must finish before persistence.
        }

        let historySnapshot = await history.recorder.snapshot()
        XCTAssertEqual(historySnapshot.historyCount, 0)
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
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
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makePatternImage(width: Int, height: Int) -> CGImage {
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
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2))
        return context.makeImage()!
    }
}

private actor FinalImageProcessorSpy: CaptureFinalImageProcessing {
    struct Invocation {
        let context: CaptureContext
        let width: Int
        let height: Int
    }

    private(set) var invocations: [Invocation] = []

    func allInvocations() -> [Invocation] { invocations }

    func processFinalImage(
        _ image: CGImage,
        context: CaptureContext,
        action: CaptureArtifactAction
    ) async throws -> CaptureArtifact {
        invocations.append(Invocation(context: context, width: image.width, height: image.height))
        return CaptureArtifact(
            storedURL: URL(fileURLWithPath: "/tmp/stored.png"),
            finalURL: URL(fileURLWithPath: "/tmp/final.png"),
            width: image.width,
            height: image.height,
            ocrText: "",
            ocrStatus: .extracted,
            redactionStatus: .notRequested,
            imageHash: nil,
            context: context,
            requestedAction: action,
            deliveryStatus: .delivered
        )
    }
}

private actor HashRecorder {
    struct Snapshot {
        let ocrImageFingerprints: [String]
        let storedImageFingerprints: [String]
        let uploadHashes: [String]
        let historyHashes: [String]
        let historyCount: Int
    }

    var ocrImageFingerprints: [String] = []
    var storedImageFingerprints: [String] = []
    var uploadHashes: [String] = []
    var historyHashes: [String] = []
    var historyCount = 0
    var storedFiles: [URL] = []

    func snapshot() -> Snapshot {
        Snapshot(
            ocrImageFingerprints: ocrImageFingerprints,
            storedImageFingerprints: storedImageFingerprints,
            uploadHashes: uploadHashes,
            historyHashes: historyHashes,
            historyCount: historyCount
        )
    }

    func recordOCRFingerprint(_ fingerprint: String) {
        ocrImageFingerprints.append(fingerprint)
    }

    func recordStoredFingerprint(_ fingerprint: String, fileURL: URL) {
        storedImageFingerprints.append(fingerprint)
        storedFiles.append(fileURL)
    }

    func recordUploadHash(_ hash: String) {
        uploadHashes.append(hash)
    }

    func recordHistoryHash(_ hash: String?) {
        historyHashes.append(hash ?? "")
        historyCount += 1
    }
}

private func imageFingerprint(_ image: CGImage) -> String {
    guard let providerData = image.dataProvider?.data else { return "" }
    return SHA256.hash(data: providerData as Data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private actor RecordingOCR: CaptureOCRExtracting {
    private let recorder: HashRecorder

    init(recorder: HashRecorder) {
        self.recorder = recorder
    }

    func extractText(from image: CGImage) async throws -> String {
        await recorder.recordOCRFingerprint(imageFingerprint(image))
        return "Recognized text"
    }
}

private struct EmptyOCR: CaptureOCRExtracting {
    func extractText(from _: CGImage) async throws -> String { "" }
}

private struct CancellingOCR: CaptureOCRExtracting {
    func extractText(from _: CGImage) async throws -> String {
        throw CancellationError()
    }
}

private actor RecordingStore: CaptureImageStoring {
    private let recorder: HashRecorder

    init(recorder: HashRecorder) {
        self.recorder = recorder
    }

    func storePNG(_ image: CGImage) async throws -> URL {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BerryShot-CaptureArtifactProcessorTests-\(UUID().uuidString).png")
        try data.write(to: fileURL, options: .atomic)
        await recorder.recordStoredFingerprint(imageFingerprint(image), fileURL: fileURL)
        return fileURL
    }
}

private struct FailingStore: CaptureImageStoring {
    enum Failure: LocalizedError {
        case writeFailed

        var errorDescription: String? { "simulated disk failure" }
    }

    func storePNG(_: CGImage) async throws -> URL {
        throw Failure.writeFailed
    }
}

private struct UnreachableStore: CaptureImageStoring {
    func storePNG(_: CGImage) async throws -> URL {
        XCTFail("Store must not run after cancellation")
        return URL(fileURLWithPath: "/tmp/unreachable.png")
    }
}

private struct CancellingRedactor: CaptureRedacting {
    func redact(_: CGImage, context _: CaptureContext, ocrResult _: OCRResult, ocrStatus _: OCRStatus) async throws -> RedactedCaptureImage {
        throw CancellationError()
    }
}

private struct UnreachableRedactor: CaptureRedacting {
    func redact(_: CGImage, context _: CaptureContext, ocrResult _: OCRResult, ocrStatus _: OCRStatus) async throws -> RedactedCaptureImage {
        XCTFail("Redactor must not run after OCR cancellation")
        throw CancellationError()
    }
}

private actor RecordingUploader: CaptureUploadProviding {
    private let recorder: HashRecorder

    init(recorder: HashRecorder) {
        self.recorder = recorder
    }

    func upload(_ request: CaptureUploadRequest) async throws -> URL {
        await recorder.recordUploadHash(try XCTUnwrap(request.imageHash))
        return URL(string: "https://example.com/final.png")!
    }
}

private struct UnreachableUploader: CaptureUploadProviding {
    func upload(_ request: CaptureUploadRequest) async throws -> URL {
        XCTFail("Uploader must not run after a store failure")
        return request.fileURL
    }
}

private struct CancellingUploader: CaptureUploadProviding {
    func upload(_: CaptureUploadRequest) async throws -> URL {
        throw CancellationError()
    }
}

@MainActor
private final class RecordingHistorySink: CaptureHistorySinking {
    let recorder: HashRecorder

    init(recorder: HashRecorder) {
        self.recorder = recorder
    }

    func record(_ artifact: CaptureArtifact) async throws {
        try Task.checkCancellation()
        await recorder.recordHistoryHash(artifact.imageHash)
    }
}

private actor HistoryRecordingGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func markEntered() {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForRelease() async {
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

@MainActor
private final class QueuedHistorySink: CaptureHistorySinking {
    private let recorder: HashRecorder
    private let gate: HistoryRecordingGate

    init(recorder: HashRecorder, gate: HistoryRecordingGate) {
        self.recorder = recorder
        self.gate = gate
    }

    func record(_ artifact: CaptureArtifact) async throws {
        await gate.markEntered()
        await gate.waitForRelease()
        try Task.checkCancellation()
        await recorder.recordHistoryHash(artifact.imageHash)
    }
}
