import Foundation
import CoreGraphics
import Vision

public protocol OCRServiceProtocol {
    func extractText(from cgImage: CGImage) async throws -> String
}

/// One recognized line of text with its confidence and the observation's
/// normalized bounding box, preserved (rather than discarded, as the plain
/// joined-string `extractText` result did) so `SensitiveContentDetector` can
/// classify sensitive content per line and map a match back to an
/// approximate on-image location. Per
/// `04-sensitive-redaction-spec.md` section 3, `normalizedBoundingBox` is
/// Vision's own convention: normalized `[0,1]`, lower-left origin, y-up.
/// Deliberately Sendable and copy-only text — nothing here is written to a
/// log or a `Codable` artifact type.
public struct RecognizedTextBlock: Sendable, Equatable {
    public let text: String
    public let confidence: Float
    public let normalizedBoundingBox: CGRectDTO

    public init(text: String, confidence: Float, normalizedBoundingBox: CGRectDTO) {
        self.text = text
        self.confidence = confidence
        self.normalizedBoundingBox = normalizedBoundingBox
    }
}

/// The rich OCR result. `text` is exactly what `extractText(from:)` already
/// returned (every block's top candidate joined with `"\n"`), so callers
/// that only need plain text see identical behavior; `blocks` is new and
/// feeds automatic sensitive-content detection.
public struct OCRResult: Sendable, Equatable {
    public let text: String
    public let blocks: [RecognizedTextBlock]

    public init(text: String, blocks: [RecognizedTextBlock]) {
        self.text = text
        self.blocks = blocks
    }
}

public final class OCRService: OCRServiceProtocol, @unchecked Sendable {
    public init() {}

    public func extractText(from cgImage: CGImage) async throws -> String {
        try await recognize(from: cgImage).text
    }

    /// Runs Vision text recognition once and preserves every observation's
    /// text, confidence, and bounding box. `.accurate` is used unconditionally
    /// (matching the previous `extractText` behavior) rather than switched
    /// per redaction policy: the spec only requires `.accurate` for the
    /// `required` policy, and always using the more thorough level is a safe
    /// superset of that minimum rather than a second mode to reason about.
    public func recognize(from cgImage: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResult(text: "", blocks: []))
                    return
                }

                var blocks: [RecognizedTextBlock] = []
                blocks.reserveCapacity(observations.count)
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    blocks.append(
                        RecognizedTextBlock(
                            text: candidate.string,
                            confidence: candidate.confidence,
                            normalizedBoundingBox: CGRectDTO(observation.boundingBox)
                        )
                    )
                }
                let text = blocks.map(\.text).joined(separator: "\n")
                continuation.resume(returning: OCRResult(text: text, blocks: blocks))
            }

            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

extension OCRService: CaptureOCRExtracting {}
