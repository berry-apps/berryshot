import Foundation

public enum OCRStatus: String, Codable, Sendable {
    case extracted
    case unavailable
}

/// Redaction is intentionally a result state rather than a Boolean claim. WP1
/// returns `.notRequested` through `NoOpCaptureRedactor`; later packages add
/// detection and rendering.
public enum RedactionStatus: String, Codable, Sendable {
    case notRequested
    case clean
    case applied
    case needsReview
    case unavailable
}

public enum CaptureArtifactAction: String, Codable, Sendable {
    case saveLocal
    case upload
}

public enum CaptureDeliveryStatus: Codable, Sendable, Equatable {
    case delivered
    case fellBackToStoredFile(errorDescription: String)
}

/// Immutable result returned only after a final (potentially redacted) image has
/// been encoded, delivered, and recorded in history.
public struct CaptureArtifact: Codable, Sendable, Equatable {
    public let storedURL: URL
    public let finalURL: URL
    public let finalPath: String
    public let width: Int
    public let height: Int
    public let ocrText: String
    public let ocrStatus: OCRStatus
    public let redactionStatus: RedactionStatus
    public let imageHash: String?
    public let context: CaptureContext
    public let requestedAction: CaptureArtifactAction
    public let deliveryStatus: CaptureDeliveryStatus

    public init(
        storedURL: URL,
        finalURL: URL,
        width: Int,
        height: Int,
        ocrText: String,
        ocrStatus: OCRStatus,
        redactionStatus: RedactionStatus,
        imageHash: String?,
        context: CaptureContext,
        requestedAction: CaptureArtifactAction,
        deliveryStatus: CaptureDeliveryStatus
    ) {
        self.storedURL = storedURL
        self.finalURL = finalURL
        self.finalPath = finalURL.path
        self.width = width
        self.height = height
        self.ocrText = ocrText
        self.ocrStatus = ocrStatus
        self.redactionStatus = redactionStatus
        self.imageHash = imageHash
        self.context = context
        self.requestedAction = requestedAction
        self.deliveryStatus = deliveryStatus
    }
}
