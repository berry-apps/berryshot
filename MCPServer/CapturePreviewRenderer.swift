import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Builds the bounded inline preview `05-mcp-server-contract.md` section 5
/// requires ("Small inline image preview for immediate model vision...
/// Full-resolution PNG is not inline by default"). This runs in the
/// `BerryShotMCP` helper, not the GUI/broker, matching
/// `02-target-architecture.md` section 2's `BerryShotMCP` responsibility
/// "Generate bounded inline previews and MCP resources" — it downsizes the
/// exact bytes already written to the artifact store (the final, already
/// redacted PNG the helper reads via a broker-issued contained path), never
/// raw/pre-redaction pixels, which never leave the GUI process
/// (`07-performance-budget.md` section 4: "Downsample preview from final
/// redacted image, never from raw pixels under required policy").
enum CapturePreviewRenderer {
    enum PreviewError: Error, Sendable {
        case decodeFailed
        case encodeFailed
    }

    /// Returns `pngData` unchanged when its longest edge already fits
    /// within `maxEdge` (never upscales a smaller image), otherwise a
    /// freshly encoded PNG downsized so its longest edge equals `maxEdge`
    /// with aspect ratio preserved.
    static func boundedPreviewPNG(from pngData: Data, maxEdge: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil) else {
            throw PreviewError.decodeFailed
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw PreviewError.decodeFailed
        }

        guard max(pixelWidth, pixelHeight) > maxEdge else {
            return pngData
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw PreviewError.decodeFailed
        }

        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw PreviewError.encodeFailed
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PreviewError.encodeFailed
        }
        return mutableData as Data
    }
}
