import Cocoa
import CoreGraphics
import CryptoKit
import Foundation

public protocol CaptureOCRExtracting: Sendable {
    func extractText(from image: CGImage) async throws -> String

    /// The richer OCR surface `CaptureArtifactProcessor` uses so a single
    /// Vision pass can serve both the plaintext `ocrText` artifact field and
    /// WP5's automatic sensitive-content detection ("one shared OCR/detection
    /// pass" per `08-implementation-work-packages.md`'s WP5 tasks), instead
    /// of running OCR twice.
    func recognize(from image: CGImage) async throws -> OCRResult
}

public extension CaptureOCRExtracting {
    /// Default bridge so every existing `CaptureOCRExtracting` conformer
    /// (every WP1-WP4 test fake, and any future minimal implementation) keeps
    /// compiling and behaving unchanged without implementing `recognize`
    /// itself. It has no bounding boxes to offer, so automatic detection
    /// simply has nothing to classify from that source; it can never
    /// fabricate a false `clean`, because `SensitiveContentDetector`
    /// distinguishes "OCR produced zero blocks" from "OCR did not complete"
    /// using the thrown-error path, not the block count. `OCRService`
    /// overrides this with the real Vision implementation that returns
    /// populated blocks.
    func recognize(from image: CGImage) async throws -> OCRResult {
        OCRResult(text: try await extractText(from: image), blocks: [])
    }
}

public protocol CaptureRedacting: Sendable {
    /// `ocrResult`/`ocrStatus` are the exact output of the processor's own
    /// (single) OCR pass for this image, passed by value at call time only —
    /// never stored in `CaptureContext` or any other `Codable` type, so a
    /// recognized block's text can never end up serialized, logged, or
    /// persisted anywhere by accident.
    func redact(_ image: CGImage, context: CaptureContext, ocrResult: OCRResult, ocrStatus: OCRStatus) async throws -> RedactedCaptureImage
}

public struct RedactedCaptureImage: @unchecked Sendable {
    public let image: CGImage
    public let status: RedactionStatus
    /// Human-readable, plaintext-free notes surfaced alongside `status` (for
    /// example the "automatic detection is unavailable" milestone warning).
    public let warnings: [String]

    public init(image: CGImage, status: RedactionStatus, warnings: [String] = []) {
        self.image = image
        self.status = status
        self.warnings = warnings
    }
}

public protocol CaptureImageStoring: Sendable {
    func storePNG(_ image: CGImage) async throws -> URL
}

public struct CaptureUploadRequest: Sendable {
    public let fileURL: URL
    public let imageHash: String?
    public let context: CaptureContext

    public init(fileURL: URL, imageHash: String?, context: CaptureContext) {
        self.fileURL = fileURL
        self.imageHash = imageHash
        self.context = context
    }
}

public protocol CaptureUploadProviding: Sendable {
    func upload(_ request: CaptureUploadRequest) async throws -> URL
}

@MainActor
public protocol CaptureHistorySinking: Sendable {
    /// Implementations must check for cancellation immediately before making
    /// history durable. `CaptureArtifactProcessor` calls this across a
    /// MainActor hop, so a task may be cancelled while that hop is queued.
    func record(_ artifact: CaptureArtifact) async throws
}

public protocol CaptureFinalImageProcessing: Sendable {
    func processFinalImage(
        _ image: CGImage,
        context: CaptureContext,
        action: CaptureArtifactAction
    ) async throws -> CaptureArtifact
}

public enum CaptureArtifactProcessorError: LocalizedError, Sendable, Equatable {
    case invalidRegionCrop
    case invalidScale
    case pngEncodingFailed
    case imageStoreFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRegionCrop:
            return "The selected capture region is outside the captured image."
        case .invalidScale:
            return "The capture scale must be greater than zero."
        case .pngEncodingFailed:
            return "The final capture image could not be encoded as PNG."
        case let .imageStoreFailed(message):
            return "The final capture image could not be saved: \(message)"
        }
    }
}

/// Crops only display-region captures. Window and scroll capture callers must
/// pass their already-final image straight to `processFinalImage`.
public func cropDisplayCapture(
    _ image: CGImage,
    region: CGRect,
    scale: CGFloat
) throws -> CGImage {
    guard scale > 0 else {
        throw CaptureArtifactProcessorError.invalidScale
    }

    // Keep the original fractional pixel coordinates. The legacy capture path
    // passed this exact scaled rectangle to Core Graphics; rounding it changes
    // the selected content for non-integral backing scales.
    let cropRect = CGRect(
        x: region.minX * scale,
        y: region.minY * scale,
        width: region.width * scale,
        height: region.height * scale
    )

    guard cropRect.width > 0, cropRect.height > 0,
          let cropped = image.cropping(to: cropRect) else {
        throw CaptureArtifactProcessorError.invalidRegionCrop
    }
    return cropped
}

/// The WP1 hook that makes the persistence ordering explicit. It never writes,
/// mutates, or claims that pixels are sanitized.
public struct NoOpCaptureRedactor: CaptureRedacting {
    public init() {}

    public func redact(_ image: CGImage, context _: CaptureContext, ocrResult _: OCRResult, ocrStatus _: OCRStatus) async throws -> RedactedCaptureImage {
        RedactedCaptureImage(image: image, status: .notRequested)
    }
}

public actor CaptureArtifactProcessor: CaptureFinalImageProcessing {
    private let ocr: any CaptureOCRExtracting
    private let redactor: any CaptureRedacting
    private let imageStore: any CaptureImageStoring
    private let uploadProvider: any CaptureUploadProviding
    private let historySink: any CaptureHistorySinking

    public init(
        ocr: any CaptureOCRExtracting,
        redactor: any CaptureRedacting,
        imageStore: any CaptureImageStoring,
        uploadProvider: any CaptureUploadProviding,
        historySink: any CaptureHistorySinking
    ) {
        self.ocr = ocr
        self.redactor = redactor
        self.imageStore = imageStore
        self.uploadProvider = uploadProvider
        self.historySink = historySink
    }

    /// This actor is intentionally separate from `MainActor`. Its synchronous
    /// OCR, PNG encoding, file I/O, and hashing work therefore execute on the
    /// capture-processing actor instead of the UI actor. History persistence
    /// remains a deliberate main-actor hop after the artifact is complete.
    ///
    /// OCR and redaction run while the raw image is still memory-only. The only
    /// image stored or delivered is the redactor's final image.
    public func processFinalImage(
        _ image: CGImage,
        context: CaptureContext,
        action: CaptureArtifactAction
    ) async throws -> CaptureArtifact {
        try Task.checkCancellation()

        let ocrResult: OCRResult
        let ocrText: String
        let ocrStatus: OCRStatus
        do {
            // One shared OCR pass: its blocks feed the redactor's automatic
            // detection below, and its joined text becomes the artifact's
            // `ocrText`, instead of running Vision a second time.
            ocrResult = try await ocr.recognize(from: image)
            ocrText = ocrResult.text
            ocrStatus = .extracted
        } catch is CancellationError {
            // OCR is optional, but cancellation is a control-flow signal. Do
            // not turn it into an "unavailable" OCR result and continue to
            // persist a capture the caller no longer wants.
            throw CancellationError()
        } catch {
            // Preserve existing behavior: OCR failure does not discard a capture.
            ocrResult = OCRResult(text: "", blocks: [])
            ocrText = ""
            ocrStatus = .unavailable
        }

        try Task.checkCancellation()
        let redacted = try await redactor.redact(image, context: context, ocrResult: ocrResult, ocrStatus: ocrStatus)
        try Task.checkCancellation()

        let storedURL: URL
        do {
            storedURL = try await imageStore.storePNG(redacted.image)
        } catch let error as CaptureArtifactProcessorError {
            throw error
        } catch {
            throw CaptureArtifactProcessorError.imageStoreFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
        // Hash the persisted final PNG rather than asking Core Graphics for its
        // backing data. `CGDataProvider.data` materializes an entire pixel
        // buffer, which is especially costly for tall scroll captures.
        let imageHash = CaptureImageHasher.hash(fileAt: storedURL)
        let finalURL: URL
        let deliveryStatus: CaptureDeliveryStatus
        do {
            finalURL = try await uploadProvider.upload(
                CaptureUploadRequest(fileURL: storedURL, imageHash: imageHash, context: context)
            )
            deliveryStatus = .delivered
        } catch is CancellationError {
            // Cancellation is not a delivery failure. Propagate it so the
            // caller does not fall back to local history for an abandoned job.
            throw CancellationError()
        } catch {
            // Preserve the existing upload fallback: retain and record the local
            // stored capture when delivery fails.
            finalURL = storedURL
            deliveryStatus = .fellBackToStoredFile(errorDescription: error.localizedDescription)
        }

        try Task.checkCancellation()
        let artifact = CaptureArtifact(
            storedURL: storedURL,
            finalURL: finalURL,
            width: redacted.image.width,
            height: redacted.image.height,
            ocrText: ocrText,
            ocrStatus: ocrStatus,
            redactionStatus: redacted.status,
            redactionWarnings: redacted.warnings,
            imageHash: imageHash,
            context: context,
            requestedAction: action,
            deliveryStatus: deliveryStatus
        )
        // This check covers cancellation before the MainActor hop. The sink
        // checks again immediately before its durable write, which covers a
        // cancellation that arrives while this task is queued for MainActor.
        try Task.checkCancellation()
        try await historySink.record(artifact)
        try Task.checkCancellation()
        return artifact
    }
}

/// Keeps source-specific routing testable while ensuring that window and scroll
/// callers have no path through display-region crop coordinates.
public actor CaptureArtifactProcessingRouter {
    private let finalImageProcessor: any CaptureFinalImageProcessing

    public init(finalImageProcessor: any CaptureFinalImageProcessing) {
        self.finalImageProcessor = finalImageProcessor
    }

    public func processRegionDisplayCapture(
        _ image: CGImage,
        region: CGRect,
        scale: CGFloat,
        context: CaptureContext,
        action: CaptureArtifactAction
    ) async throws -> CaptureArtifact {
        let cropped = try cropDisplayCapture(image, region: region, scale: scale)
        return try await finalImageProcessor.processFinalImage(cropped, context: context, action: action)
    }

    public func processFinalImage(
        _ image: CGImage,
        context: CaptureContext,
        action: CaptureArtifactAction
    ) async throws -> CaptureArtifact {
        try await finalImageProcessor.processFinalImage(image, context: context, action: action)
    }
}

public enum CaptureImageHasher {
    /// Hash a persisted final image with fixed-size reads. Hashing failure is
    /// non-fatal metadata loss: the capture may still be uploaded and recorded.
    /// This deliberately avoids `CGDataProvider.data`, which copies the whole
    /// image backing buffer before any bytes can be hashed.
    public static func hash(fileAt fileURL: URL) -> String? {
        guard let input = InputStream(url: fileURL) else { return nil }
        input.open()
        defer { input.close() }

        var hasher = SHA256()
        let chunkSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        while input.hasBytesAvailable {
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                input.read(pointer.baseAddress!, maxLength: pointer.count)
            }
            if count < 0 { return nil }
            if count == 0 { break }
            hasher.update(data: Data(buffer[0..<count]))
        }

        guard input.streamError == nil else { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct DefaultCaptureImageStore: CaptureImageStoring {
    public init() {}

    public func storePNG(_ image: CGImage) async throws -> URL {
        let bitmapImage = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw CaptureArtifactProcessorError.pngEncodingFailed
        }

        let fileManager = FileManager.default
        guard let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CaptureArtifactProcessorError.imageStoreFailed("Application Support is unavailable")
        }
        let appDirectory = appSupportDirectory.appendingPathComponent("BerryShot", isDirectory: true)

        do {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            let fileURL = appDirectory.appendingPathComponent("Screenshot-\(UUID().uuidString).png")
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            throw CaptureArtifactProcessorError.imageStoreFailed(error.localizedDescription)
        }
    }
}

public struct CurrentCaptureUploadProvider: CaptureUploadProviding {
    public init() {}

    public func upload(_ request: CaptureUploadRequest) async throws -> URL {
        let service = await UploadServiceFactory.currentService()
        return try await service.uploadImage(fileURL: request.fileURL)
    }
}

@MainActor
public final class SwiftDataCaptureHistorySink: CaptureHistorySinking {
    public init() {}

    public func record(_ artifact: CaptureArtifact) async throws {
        // The calling task can be cancelled after the processor's pre-hop
        // check while it waits to enter MainActor. Do not create a history row
        // for work the caller has abandoned.
        try Task.checkCancellation()
        let screenshot = ScreenshotModel(
            imagePath: artifact.finalPath,
            thumbnailPath: artifact.finalPath,
            width: artifact.width,
            height: artifact.height,
            ocrText: artifact.ocrText,
            redactionStatus: artifact.redactionStatus.rawValue
        )
        HistoryService.shared.save(screenshot)
    }
}
