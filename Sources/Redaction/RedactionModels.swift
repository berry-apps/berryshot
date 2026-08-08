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

/// WP4 shipped only user-drawn manual regions. WP5 adds the automatically
/// detected categories from `04-sensitive-redaction-spec.md` section 3:
/// AX secure fields, and Vision-classified emails, phone numbers, validated
/// card numbers, API/token prefixes, and user-configured literal terms.
public enum SensitiveCategory: String, Codable, Sendable {
    case manual
    case secureField
    case email
    case phoneNumber
    case creditCard
    case apiToken
    case customTerm
}

/// WP4 shipped only the manual detection source. WP5 adds the accessibility
/// and Vision OCR sources.
public enum RedactionSource: String, Codable, Sendable {
    case manual
    case accessibility
    case visionOCR
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

    /// Unions overlapping rectangles that share a style into as few
    /// rectangles as possible. WP4 only ever merged manual regions, so it
    /// could re-tag every merged result `.manual`/`.manual`/`1.0`
    /// unconditionally. WP5 mixes automatically detected categories
    /// (AX/Vision) into the same pool, so a merged rectangle now keeps the
    /// category/source/confidence of whichever *contributing* region had the
    /// highest confidence — never averaged or silently dropped, since spec
    /// section 3 requires every region to still record exactly one
    /// category/confidence/source. This can under-represent a merged area
    /// (a lower-confidence contributor's category is not separately
    /// recorded), which is the same "approximate, not a complete audit
    /// trail" tradeoff the spec already accepts for substring bounding
    /// boxes.
    private static func mergeOverlapping(_ regions: [RedactionRegion], style: RedactionStyle) -> [RedactionRegion] {
        var groups: [[RedactionRegion]] = regions.map { [$0] }

        var didMerge = true
        while didMerge {
            didMerge = false
            scan: for i in 0..<groups.count {
                for j in (i + 1)..<groups.count {
                    if unionRect(of: groups[i]).intersects(unionRect(of: groups[j])) {
                        groups[i] += groups[j]
                        groups.remove(at: j)
                        didMerge = true
                        break scan
                    }
                }
            }
        }

        return groups.map { members in
            // `max(by:)` always has a result here because every group has at
            // least one member (`regions.map { [$0] }` above).
            let strongest = members.max { $0.confidence < $1.confidence }!
            return RedactionRegion(
                normalizedRect: CGRectDTO(unionRect(of: members)),
                category: strongest.category,
                confidence: strongest.confidence,
                source: strongest.source,
                style: style
            )
        }
    }

    private static func unionRect(of members: [RedactionRegion]) -> CGRect {
        let rects = members.map(\.normalizedRect.cgRect)
        return rects.dropFirst().reduce(rects[0]) { $0.union($1) }
    }
}
