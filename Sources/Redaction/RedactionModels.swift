import CoreGraphics
import Foundation

/// Visual treatment applied to a redacted region.
///
/// Matches `docs/architecture/feature/app-capture-mcp/04-sensitive-redaction-spec.md`
/// section 1 exactly. `RedactionStatus` (`Capture/CaptureArtifact.swift`) and
/// `RedactionPolicy` (`Capture/CaptureContext.swift`) already exist from WP1
/// and already match the spec, so only `RedactionStyle` and the region model
/// are new here.
public enum RedactionStyle: String, Codable, Sendable, CaseIterable {
    case blur
    case pixelate
    case solid
}

/// WP4 ships only user-drawn manual regions. WP5 is expected to extend this
/// set with automatically detected categories (secure fields, emails, cards,
/// tokens, ...); adding those cases now would be an undocumented automatic
/// detection claim this work package does not implement.
public enum SensitiveCategory: String, Codable, Sendable {
    case manual
}

/// WP4 ships only the manual detection source. WP5 adds accessibility and
/// Vision OCR sources.
public enum RedactionSource: String, Codable, Sendable {
    case manual
}

/// One rectangle to flatten before persistence. Deliberately carries no
/// recognized text/value — only geometry, category, confidence, source, and
/// the requested visual style — per the spec's "never store recognized secret
/// content in `RedactionRegion`" rule.
///
/// `normalizedRect` is top-left-origin, y-down (0,0 is the top-left corner of
/// the image, 1,1 is the bottom-right), matching the coordinate convention
/// the spec documents for the Vision conversion in section 3. Core Image's
/// own coordinate space is bottom-left-origin, y-up; `RedactionRenderer`
/// performs that conversion, not the caller.
public struct RedactionRegion: Codable, Sendable, Equatable {
    public let normalizedRect: CGRectDTO
    public let category: SensitiveCategory
    public let confidence: Double
    public let source: RedactionSource
    public let style: RedactionStyle

    public init(
        normalizedRect: CGRectDTO,
        category: SensitiveCategory,
        confidence: Double,
        source: RedactionSource,
        style: RedactionStyle
    ) {
        self.normalizedRect = normalizedRect
        self.category = category
        self.confidence = confidence
        self.source = source
        self.style = style
    }

    /// A user-drawn rectangle. Confidence is `1.0` because the user placed it
    /// explicitly; there is nothing to infer.
    public static func manual(normalizedRect: CGRectDTO, style: RedactionStyle) -> RedactionRegion {
        RedactionRegion(
            normalizedRect: normalizedRect,
            category: .manual,
            confidence: 1.0,
            source: .manual,
            style: style
        )
    }
}

/// Merges overlapping regions before rendering, per spec section 3 ("Merge
/// overlapping/padded rectangles before rendering"). Regions are only merged
/// with other regions that request the same style: collapsing two rectangles
/// that asked for different treatments would silently discard the user's
/// choice for part of the covered area, which the spec's "no silent fallback"
/// guard forbids.
public enum RedactionRegionMerger {
    public static func merge(_ regions: [RedactionRegion]) -> [RedactionRegion] {
        var buckets: [RedactionStyle: [RedactionRegion]] = [:]
        for region in regions {
            buckets[region.style, default: []].append(region)
        }

        var merged: [RedactionRegion] = []
        for (style, group) in buckets {
            merged.append(contentsOf: mergeOverlapping(group, style: style))
        }
        return merged
    }

    /// WP4 only ever merges manual regions, so the merged result is always
    /// re-tagged `.manual`/`.manual`/`1.0`. A future work package that mixes
    /// automatically detected categories into the same merge pass will need
    /// to decide how to combine category/confidence/source instead of
    /// reusing this shortcut.
    private static func mergeOverlapping(_ regions: [RedactionRegion], style: RedactionStyle) -> [RedactionRegion] {
        var rects = regions.map(\.normalizedRect.cgRect)

        var didMerge = true
        while didMerge {
            didMerge = false
            scan: for i in 0..<rects.count {
                for j in (i + 1)..<rects.count {
                    if rects[i].intersects(rects[j]) {
                        rects[i] = rects[i].union(rects[j])
                        rects.remove(at: j)
                        didMerge = true
                        break scan
                    }
                }
            }
        }

        return rects.map {
            RedactionRegion(normalizedRect: CGRectDTO($0), category: .manual, confidence: 1.0, source: .manual, style: style)
        }
    }
}
