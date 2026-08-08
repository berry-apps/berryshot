import Cocoa
import CoreGraphics
import Foundation
import BerryShotIPC

/// Narrow seam over `WindowCaptureService.captureWindow(_:)` (WP2), kept
/// separate from `CaptureBrokerDiscovering` because it is the one call in
/// this file that actually drives ScreenCaptureKit, so
/// `CaptureBrokerTests`-style tests can fake it with an in-memory `CGImage`
/// fixture instead of requiring Screen Recording permission.
public protocol CaptureBrokerWindowCapturing: Sendable {
    func captureWindow(_ descriptor: WindowDescriptor) async throws -> RawCapturedWindow
}

public struct LiveCaptureBrokerWindowCapturing: CaptureBrokerWindowCapturing {
    public init() {}

    public func captureWindow(_ descriptor: WindowDescriptor) async throws -> RawCapturedWindow {
        try await WindowCaptureService.shared.captureWindow(descriptor)
    }
}

/// Narrow seam over WP4/WP5's redaction pipeline, parameterized by `style`
/// because — unlike `SensitiveCategory` enablement, which stays a
/// GUI-persisted `RedactionSettings` preference — `redaction_style` is a
/// per-call MCP tool argument (`05-mcp-server-contract.md` section 3) that
/// must always be honored exactly as requested, never silently overridden
/// by whatever style the GUI's Privacy settings currently have selected.
public protocol CaptureBrokerRedacting: Sendable {
    func redact(
        _ image: CGImage,
        context: CaptureContext,
        ocrResult: OCRResult,
        ocrStatus: OCRStatus,
        style: RedactionStyle
    ) async throws -> RedactedCaptureImage
}

/// Composes the GUI's persisted enabled-category/custom-term settings with
/// the request's own style, and otherwise runs the exact same AX + Vision
/// detection `SensitiveContentPolicyRedactor` (WP5) already implements for
/// the main capture pipeline. A fresh `SensitiveContentPolicyRedactor` is
/// constructed per call because `style` varies per call; its `renderer`
/// still defaults to `RedactionRenderer.sharedCIContext`, so this does not
/// create a new `CIContext` per capture.
public struct LiveCaptureBrokerRedacting: CaptureBrokerRedacting {
    public init() {}

    public func redact(
        _ image: CGImage,
        context: CaptureContext,
        ocrResult: OCRResult,
        ocrStatus: OCRStatus,
        style: RedactionStyle
    ) async throws -> RedactedCaptureImage {
        let redactor = SensitiveContentPolicyRedactor(configurationProvider: {
            let base = await RedactionSettings.shared.detectionConfiguration()
            return SensitiveDetectionConfiguration(
                enabledCategories: base.enabledCategories,
                customTerms: base.customTerms,
                customTermsCaseSensitive: base.customTermsCaseSensitive,
                style: style
            )
        })
        return try await redactor.redact(image, context: context, ocrResult: ocrResult, ocrStatus: ocrStatus)
    }
}

/// The full capture-window pipeline WP7 adds behind `CaptureBroker`:
/// capture pixels (WP2) -> conditional OCR -> redact (WP4/WP5) -> encode ->
/// persist into `CaptureArtifactStore`. `CaptureBroker` resolves/validates
/// the requested window itself (reusing the same `discovery` dependency
/// `listWindows` already uses) and passes the already-matched descriptor
/// in, so this protocol only owns the parts that are genuinely new in WP7.
public protocol CaptureBrokerCaptureOperating: Sendable {
    func captureWindow(_ request: CaptureWindowRequest, matchedWindow: WindowDescriptor) async throws -> CaptureManifestDTO
}

public struct LiveCaptureBrokerCaptureOperations: CaptureBrokerCaptureOperating {
    private let capturing: any CaptureBrokerWindowCapturing
    private let ocr: any CaptureOCRExtracting
    private let redacting: any CaptureBrokerRedacting
    private let store: CaptureArtifactStore

    public init(
        store: CaptureArtifactStore,
        capturing: any CaptureBrokerWindowCapturing = LiveCaptureBrokerWindowCapturing(),
        ocr: any CaptureOCRExtracting = OCRService(),
        redacting: any CaptureBrokerRedacting = LiveCaptureBrokerRedacting()
    ) {
        self.store = store
        self.capturing = capturing
        self.ocr = ocr
        self.redacting = redacting
    }

    public func captureWindow(_ request: CaptureWindowRequest, matchedWindow: WindowDescriptor) async throws -> CaptureManifestDTO {
        let raw: RawCapturedWindow
        do {
            raw = try await capturing.captureWindow(matchedWindow)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CaptureError {
            throw Self.mapCaptureError(error)
        } catch {
            throw BrokerOperationError(code: .internalError, message: "Capture failed")
        }

        try Task.checkCancellation()

        let policy = request.redactionPolicy.corePolicy
        let style = request.redactionStyle.coreStyle
        // Performance budget fast path (`07-performance-budget.md` section 2:
        // "Warm single-window capture without OCR/redaction... below 500 ms"):
        // Vision only runs when the caller explicitly asked for OCR text or
        // when redaction needs it to classify text-based sensitive
        // categories. `redactionPolicy == .none` never needs OCR at all —
        // `CaptureBrokerRedacting` returns `.notRequested` immediately
        // without inspecting `ocrResult` in that case.
        let needsOCR = request.ocr || policy != .none

        let ocrResult: OCRResult
        let ocrStatus: OCRStatus
        if needsOCR {
            do {
                ocrResult = try await ocr.recognize(from: raw.image)
                ocrStatus = .extracted
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Mirrors CaptureArtifactProcessor: OCR failure does not
                // discard the capture, it just narrows what redaction can
                // verify (surfaced as `needsReview`/`unavailable` by the
                // redactor itself when policy requires it).
                ocrResult = OCRResult(text: "", blocks: [])
                ocrStatus = .unavailable
            }
        } else {
            ocrResult = OCRResult(text: "", blocks: [])
            ocrStatus = .unavailable
        }

        try Task.checkCancellation()

        let context = CaptureContext.applicationWindow(
            windowID: matchedWindow.id,
            bundleIdentifier: matchedWindow.bundleIdentifier,
            applicationName: matchedWindow.applicationName,
            windowTitle: matchedWindow.title,
            processID: matchedWindow.processID,
            windowContentRectInScreenPoints: raw.contentRectInPoints,
            redactionPolicy: policy,
            manualRedactionRegions: []
        )

        let redacted: RedactedCaptureImage
        do {
            redacted = try await redacting.redact(raw.image, context: context, ocrResult: ocrResult, ocrStatus: ocrStatus, style: style)
        } catch is CancellationError {
            throw CancellationError()
        } catch is RedactionRequiredError {
            throw BrokerOperationError(
                code: .redactionReviewRequired,
                message: "Sensitive-content redaction is required, but automatic detection did not complete a safe result for this capture"
            )
        } catch is RedactionRendererError {
            throw BrokerOperationError(code: .redactionUnavailable, message: "Redaction could not be rendered for this capture")
        } catch {
            throw BrokerOperationError(code: .redactionUnavailable, message: "Redaction failed for this capture")
        }

        try Task.checkCancellation()

        guard let pngData = Self.encodePNG(redacted.image) else {
            throw BrokerOperationError(code: .internalError, message: "The final capture image could not be encoded")
        }

        try Task.checkCancellation()

        // OCR resource publication is opt-in even when OCR ran internally
        // for redaction detection (`05-mcp-server-contract.md` section 6).
        let publishOCR = request.ocr && ocrStatus == .extracted

        do {
            return try await store.store(
                imageData: pngData,
                ocrText: publishOCR ? ocrResult.text : nil,
                bundleIdentifier: matchedWindow.bundleIdentifier,
                processID: matchedWindow.processID,
                windowID: matchedWindow.id,
                windowTitle: matchedWindow.title,
                pixelWidth: redacted.image.width,
                pixelHeight: redacted.image.height,
                pointPixelScale: raw.pointPixelScale,
                redactionStatus: IPCRedactionStatus(coreStatus: redacted.status),
                redactionRegionCount: redacted.regionCount,
                warnings: redacted.warnings
            )
        } catch is CaptureArtifactStore.StoreError {
            throw BrokerOperationError(code: .internalError, message: "The capture could not be stored")
        }
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let bitmapImage = NSBitmapImageRep(cgImage: image)
        return bitmapImage.representation(using: .png, properties: [:])
    }

    private static func mapCaptureError(_ error: CaptureError) -> BrokerOperationError {
        switch error {
        case .permissionDenied:
            return BrokerOperationError(code: .permissionDenied, message: "Screen Recording permission is required to capture content")
        case .windowNotAvailable, .noWindowFound, .windowStale:
            return BrokerOperationError(code: .windowNotAvailable, message: "The requested window is not currently available")
        case .windowIdentityChanged:
            return BrokerOperationError(code: .windowIdentityChanged, message: "The window no longer belongs to the expected application")
        case .noDisplayFound, .captureFailed:
            return BrokerOperationError(code: .internalError, message: "Capture failed")
        }
    }
}
