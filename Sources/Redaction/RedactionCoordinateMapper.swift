import CoreGraphics
import Foundation

/// Centralizes every coordinate conversion `SensitiveContentDetector` needs,
/// per `04-sensitive-redaction-spec.md` section 3's "Centralize conversion"
/// instruction. Getting either conversion backwards would silently redact
/// the wrong part of the image, so both directions are pinned here with unit
/// tests instead of being reimplemented ad hoc at each call site.
public enum RedactionCoordinateMapper {
    /// Converts a Vision `VNRecognizedTextObservation.boundingBox` (normalized,
    /// lower-left origin, y-up — Apple's Vision convention) into pixel
    /// coordinates in the final image's top-left-origin, y-down space, using
    /// the exact formula from the spec:
    ///
    /// ```text
    /// x = minX × imageWidth
    /// y = (1 - maxY) × imageHeight
    /// width = boxWidth × imageWidth
    /// height = boxHeight × imageHeight
    /// ```
    public static func imagePixelRect(
        forVisionNormalizedBox box: CGRect,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect {
        let width = Double(imageWidth)
        let height = Double(imageHeight)
        return CGRect(
            x: box.minX * width,
            y: (1 - box.maxY) * height,
            width: box.width * width,
            height: box.height * height
        )
    }

    /// Converts an image-pixel rect (top-left origin, y-down) into the
    /// normalized `[0,1]` top-left rect that `RedactionRegion.normalizedRect`
    /// expects. Returns `.zero` for a non-positive image size rather than
    /// dividing by zero.
    public static func normalizedRect(
        forImagePixelRect rect: CGRect,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect {
        guard imageWidth > 0, imageHeight > 0 else { return .zero }
        let width = Double(imageWidth)
        let height = Double(imageHeight)
        return CGRect(
            x: rect.minX / width,
            y: rect.minY / height,
            width: rect.width / width,
            height: rect.height / height
        )
    }

    /// Converts an AX element frame in screen points into a normalized
    /// `[0,1]` top-left rect relative to the captured window's content rect.
    ///
    /// Both `elementFrame` and `contentRect` are expected in the same
    /// "global display" coordinate space — top-left origin at the primary
    /// display, y increasing downward. This is the convention
    /// `AXUIElementCopyAttributeValue(kAXPositionAttribute)`,
    /// `SCWindow.frame`, and `SCContentFilter.contentRect` all share (see
    /// `01-scope-current-state.md` section 5's linked Apple documentation);
    /// it is also the convention this codebase already assumes elsewhere,
    /// for example `CaptureCoordinator.globalRect(fromLocal:on:)`'s "global
    /// top-left display coordinates" comment. No axis flip is needed here —
    /// only translation by the content rect's origin and scaling by its size.
    ///
    /// Returns `nil` when the content rect is degenerate or the element does
    /// not overlap the captured content at all (for example a secure field
    /// in a different window than the one captured).
    public static func normalizedRect(
        forElementFrameInScreenPoints elementFrame: CGRect,
        windowContentRectInScreenPoints contentRect: CGRect
    ) -> CGRect? {
        guard contentRect.width > 0, contentRect.height > 0 else { return nil }
        let clipped = elementFrame.intersection(contentRect)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return CGRect(
            x: (clipped.minX - contentRect.minX) / contentRect.width,
            y: (clipped.minY - contentRect.minY) / contentRect.height,
            width: clipped.width / contentRect.width,
            height: clipped.height / contentRect.height
        )
    }

    /// Outsets a pixel rect by a category-specific pad (see
    /// `SensitiveContentDetector.paddingPixels(for:)`) before it is
    /// normalized. Applied before clamping so padding near an edge is
    /// trimmed rather than wrapped or rejected.
    public static func padded(_ rect: CGRect, byPixels pad: Double) -> CGRect {
        guard pad != 0 else { return rect }
        return rect.insetBy(dx: -pad, dy: -pad)
    }

    /// Clamps a normalized rect to the unit square `[0,1] × [0,1]`, per spec
    /// section 3's "clamp to image bounds". `CGRect.intersection` returns
    /// `.null` (not a zero-sized rect at a defined origin) when there is no
    /// overlap at all; that would otherwise propagate non-finite values into
    /// `CGRectDTO`, so it is normalized to `.zero` here.
    public static func clampedToUnitSquare(_ rect: CGRect) -> CGRect {
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return clamped.isNull ? .zero : clamped
    }
}
