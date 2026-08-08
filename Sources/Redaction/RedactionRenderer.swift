import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

public enum RedactionRendererError: LocalizedError, Sendable, Equatable {
    case invalidImage
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The image to redact was invalid."
        case .renderFailed:
            return "The redacted image could not be rendered."
        }
    }
}

/// Flattens redaction regions into pixels per
/// `04-sensitive-redaction-spec.md` section 4: one `CIImage` from the raw
/// `CGImage`, a mask for the merged rectangles, the style-specific filter,
/// `CIBlendWithMask` to combine it with the untouched background, a final
/// crop back to the original extent (blur/pixelate can otherwise expand
/// sample bounds), and one render through a single reused `CIContext`.
///
/// `RedactionRegion.normalizedRect` is top-left-origin/y-down; Core Image's
/// own coordinate space is bottom-left-origin/y-up, so `pixelRect(for:...)`
/// performs that flip. This was verified empirically against this toolchain
/// before implementation (see the WP4 issue's "Documentation consulted"
/// section) rather than assumed, because getting it backwards would silently
/// redact the wrong part of the image.
public struct RedactionRenderer: Sendable {
    /// Strong enough that fixture text is not legible after blur, per the
    /// spec's "no blur radius so small that text remains readable" guard.
    public static let blurRadius: Double = 30
    public static let pixellateScale: Double = 24

    /// One process-wide `CIContext`, created lazily and reused for every
    /// operation. Creating a `CIContext` is expensive and the spec forbids a
    /// new context per region; `.workingColorSpace: NSNull()` keeps rendering
    /// a direct, deterministic device-RGB passthrough instead of a
    /// color-managed transform.
    /// `public` because a default argument expression must be at least as
    /// visible as the initializer it appears on.
    public static let sharedCIContext = CIContext(options: [.workingColorSpace: NSNull()])

    private let context: CIContext

    public init(context: CIContext = RedactionRenderer.sharedCIContext) {
        self.context = context
    }

    /// Flattens every region into `image`. Regions are expected to already be
    /// merged (see `RedactionRegionMerger`); this function still tolerates
    /// unmerged input since blending order does not change the visible
    /// result. Returns the original `image` unchanged when `regions` is
    /// empty.
    public func flatten(_ image: CGImage, regions: [RedactionRegion]) throws -> CGImage {
        guard !regions.isEmpty else { return image }
        guard image.width > 0, image.height > 0 else { throw RedactionRendererError.invalidImage }

        var working = CIImage(cgImage: image)
        let extent = working.extent

        for region in regions {
            let maskRect = Self.pixelRect(for: region.normalizedRect, imageWidth: image.width, imageHeight: image.height)
                .intersection(extent)
            guard maskRect.width > 0, maskRect.height > 0 else { continue }
            working = try apply(style: region.style, to: working, maskRect: maskRect, fullExtent: extent)
        }

        let cropped = working.cropped(to: extent)
        guard let cgImage = context.createCGImage(cropped, from: extent) else {
            throw RedactionRendererError.renderFailed
        }
        return cgImage
    }

    /// Converts a top-left-origin/y-down normalized rectangle into a
    /// bottom-left-origin/y-up pixel rectangle suitable for Core Image
    /// masking. `internal` (not `private`) so tests can verify the mapping
    /// directly against known coordinates, independent of a full render.
    static func pixelRect(for normalized: CGRectDTO, imageWidth: Int, imageHeight: Int) -> CGRect {
        let width = Double(imageWidth)
        let height = Double(imageHeight)
        let topLeftDown = CGRect(
            x: normalized.x * width,
            y: normalized.y * height,
            width: normalized.width * width,
            height: normalized.height * height
        )
        return CGRect(
            x: topLeftDown.minX,
            y: height - topLeftDown.maxY,
            width: topLeftDown.width,
            height: topLeftDown.height
        )
    }

    /// Builds the style-specific foreground, then blends it with the
    /// untouched background using a mask local to this call. Every filter
    /// instance is created fresh here so concurrent operations never share
    /// mutable `CIFilter` state.
    private func apply(style: RedactionStyle, to source: CIImage, maskRect: CGRect, fullExtent: CGRect) throws -> CIImage {
        let foreground: CIImage
        switch style {
        case .solid:
            foreground = CIImage(color: CIColor(red: 0.05, green: 0.05, blue: 0.05)).cropped(to: fullExtent)
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = source.clampedToExtent()
            filter.scale = Float(Self.pixellateScale)
            guard let output = filter.outputImage else { throw RedactionRendererError.renderFailed }
            foreground = output.cropped(to: fullExtent)
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = source.clampedToExtent()
            filter.radius = Float(Self.blurRadius)
            guard let output = filter.outputImage else { throw RedactionRendererError.renderFailed }
            foreground = output.cropped(to: fullExtent)
        }

        let maskImage = CIImage(color: .white).cropped(to: maskRect)
            .composited(over: CIImage(color: .black).cropped(to: fullExtent))

        let blend = CIFilter.blendWithMask()
        blend.inputImage = foreground
        blend.backgroundImage = source
        blend.maskImage = maskImage
        guard let blended = blend.outputImage else { throw RedactionRendererError.renderFailed }
        return blended.cropped(to: fullExtent)
    }
}

/// The reviewed-region result was required but unavailable.
public enum RedactionRequiredError: LocalizedError, Sendable, Equatable {
    case noReviewedRegion

    public var errorDescription: String? {
        switch self {
        case .noReviewedRegion:
            return "Sensitive-content redaction is required, but no reviewed region was available. The capture was discarded instead of exposing an unredacted image."
        }
    }
}

/// The exact warning text from `04-sensitive-redaction-spec.md` section 2's
/// required fallback milestone. Shown identically in GUI and artifact
/// metadata so the product never implies automatic coverage it does not yet
/// have.
public let automaticRedactionUnavailableWarning =
    "Automatic sensitive-content redaction is unavailable; review the image before sharing."

/// Applies the policy recorded on `CaptureContext`. WP4 has no automatic
/// AX/Vision detection yet (that ships in WP5), so the only region source is
/// the caller's manual rectangles. Honesty over completeness:
///
/// - `.none`: unchanged image, `.notRequested` — no automated claim at all.
/// - `.suggest` with no reviewed regions: unchanged image, `.needsReview` and
///   the milestone warning — never silently `.clean`.
/// - `.suggest` / `.required` with reviewed regions: flattened image,
///   `.applied`.
/// - `.required` with no reviewed regions: fails closed. No image is
///   returned; `CaptureArtifactProcessor` never reaches its store/upload/
///   history hooks for this capture.
public struct ManualRedactionPolicyRedactor: CaptureRedacting {
    private let renderer: RedactionRenderer

    public init(renderer: RedactionRenderer = RedactionRenderer()) {
        self.renderer = renderer
    }

    /// Manual-only: ignores `ocrResult`/`ocrStatus` entirely. This type keeps
    /// WP4's exact manual-region behavior; it is still used directly by Save
    /// As (see `CaptureCoordinator`), which does not run automatic
    /// detection. `SensitiveContentPolicyRedactor` (WP5) is the redactor
    /// that actually uses the OCR/AX signal for the main capture pipeline.
    public func redact(_ image: CGImage, context: CaptureContext, ocrResult _: OCRResult, ocrStatus _: OCRStatus) async throws -> RedactedCaptureImage {
        switch context.redactionPolicy {
        case .none:
            return RedactedCaptureImage(image: image, status: .notRequested)
        case .suggest:
            guard !context.manualRedactionRegions.isEmpty else {
                return RedactedCaptureImage(image: image, status: .needsReview, warnings: [automaticRedactionUnavailableWarning])
            }
            return try flatten(image, context: context)
        case .required:
            guard !context.manualRedactionRegions.isEmpty else {
                throw RedactionRequiredError.noReviewedRegion
            }
            return try flatten(image, context: context)
        }
    }

    private func flatten(_ image: CGImage, context: CaptureContext) throws -> RedactedCaptureImage {
        let merged = RedactionRegionMerger.merge(context.manualRedactionRegions)
        let flattened = try renderer.flatten(image, regions: merged)
        return RedactedCaptureImage(image: flattened, status: .applied)
    }
}
