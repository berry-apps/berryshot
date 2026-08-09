import Cocoa
import CoreGraphics
@preconcurrency import ApplicationServices
import Foundation

// MARK: - AX secure-field detection (frames only, never values)

/// Supplies the screen frames of secure text fields for one running
/// application, without ever reading their content. Behind a protocol so
/// `SensitiveContentDetector`/`SensitiveContentPolicyRedactor` are testable
/// with a fake tree instead of requiring a live, trusted Accessibility
/// session in unit tests.
public protocol SecureFieldFrameProviding: Sendable {
    /// Whether this process currently has Accessibility trust
    /// (`AXIsProcessTrusted()`). Checked separately from
    /// `secureFieldFrames(processID:)` so a caller can distinguish "scanned
    /// and found zero secure fields" from "could not scan at all" — the
    /// distinction spec section 8's "No `clean` result based only on absent
    /// AX nodes" guard depends on.
    var isAccessibilityTrusted: Bool { get }

    /// Frames only, in screen points (top-left origin, y-down — the same
    /// convention `SCWindow.frame`/`SCContentFilter.contentRect` use; see
    /// `RedactionCoordinateMapper`). Implementations must never read
    /// `kAXValueAttribute` for a secure field, only role/subrole/position/
    /// size.
    func secureFieldFrames(processID: Int32) -> [CGRect]
}

/// Real Accessibility-backed implementation. Traversal is bounded by both
/// depth and total visited-node count (mirroring the existing bounded
/// traversal in `AccessibilityBridge.findScrollArea`) so a pathological or
/// enormous AX tree cannot hang a capture.
public struct AXSecureFieldFrameProvider: SecureFieldFrameProviding {
    private let maxDepth: Int
    private let maxVisitedNodes: Int

    public init(maxDepth: Int = 40, maxVisitedNodes: Int = 4000) {
        self.maxDepth = maxDepth
        self.maxVisitedNodes = maxVisitedNodes
    }

    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Returns an empty array without attempting any AX call at all when
    /// this process is not trusted, rather than relying on every downstream
    /// `AXUIElementCopyAttributeValue` call to fail gracefully on its own.
    public func secureFieldFrames(processID: Int32) -> [CGRect] {
        guard isAccessibilityTrusted else { return [] }
        let appElement = AXUIElementCreateApplication(processID)
        var frames: [CGRect] = []
        var visited = 0
        collectSecureFieldFrames(appElement, depth: 0, visited: &visited, into: &frames)
        return frames
    }

    private func collectSecureFieldFrames(_ element: AXUIElement, depth: Int, visited: inout Int, into frames: inout [CGRect]) {
        guard depth < maxDepth, visited < maxVisitedNodes else { return }
        visited += 1

        if isSecureTextField(element) {
            // A secure field's value is never read here — only role/subrole
            // (already checked by `isSecureTextField`) and geometry.
            if let frame = frame(of: element) {
                frames.append(frame)
            }
            // Secure fields have no useful children to redact separately.
            return
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children {
            collectSecureFieldFrames(child, depth: depth + 1, visited: &visited, into: &frames)
        }
    }

    private func isSecureTextField(_ element: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
              let subrole = subroleRef as? String else { return false }
        return subrole == kAXSecureTextFieldSubrole
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              // swiftlint:disable:next force_cast
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

// MARK: - Pure detection composition

/// User/product configuration `SensitiveContentDetector` needs. Built from
/// `RedactionSettings` in the running app; constructed directly in tests.
public struct SensitiveDetectionConfiguration: Sendable {
    public let enabledCategories: Set<SensitiveCategory>
    public let customTerms: [String]
    public let customTermsCaseSensitive: Bool
    public let style: RedactionStyle

    public init(
        enabledCategories: Set<SensitiveCategory>,
        customTerms: [String],
        customTermsCaseSensitive: Bool,
        style: RedactionStyle
    ) {
        self.enabledCategories = enabledCategories
        self.customTerms = customTerms
        self.customTermsCaseSensitive = customTermsCaseSensitive
        self.style = style
    }
}

/// Whether every *applicable, enabled* detector source actually completed.
/// `SensitiveContentPolicyRedactor` uses this — not just whether any region
/// was found — to decide between `.clean`, `.needsReview`, and
/// `.unavailable`, per WP5 task 9 ("Set `clean` only when the configured
/// detector set completed successfully ... otherwise use
/// `needsReview`/`unavailable`").
public enum DetectionCompleteness: Sendable, Equatable {
    /// Every enabled, applicable source ran to completion.
    case complete
    /// OCR completed, but an enabled, applicable AX check could not run
    /// (Accessibility not trusted). A genuine but partial gap.
    case partiallyIncomplete
    /// OCR itself did not complete, so text-based categories could not be
    /// checked at all — the more severe gap.
    case unavailable
}

public struct SensitiveDetectionOutcome: Sendable {
    public let regions: [RedactionRegion]
    public let completeness: DetectionCompleteness
    /// Human-readable, plaintext-free notes. Never contains recognized text.
    public let warnings: [String]
}

/// Composes AX and Vision OCR signals into `RedactionRegion`s. Pure and
/// synchronous: it never touches AXUIElement/Vision APIs directly — callers
/// supply already-collected frames/blocks — so it is fully unit-testable
/// with fixtures, independent of live permissions or a real capture.
public enum SensitiveContentDetector {
    /// Padding applied around a match, in image pixels, before normalizing
    /// and clamping — "category-specific padding" per spec section 3. AX
    /// frames are already exact UI element boundaries and get a small pad
    /// only to avoid a hairline gap at the mask edge; OCR-derived matches
    /// get more, because Vision's box hugs glyph ink tightly and a thin pad
    /// can leave anti-aliased character edges visible outside the mask.
    static func paddingPixels(for category: SensitiveCategory) -> Double {
        switch category {
        case .secureField: return 2
        case .creditCard, .apiToken: return 4
        case .email, .phoneNumber, .customTerm: return 3
        case .manual: return 0
        }
    }

    private static let ocrDerivedCategories: Set<SensitiveCategory> = [.email, .phoneNumber, .creditCard, .apiToken, .customTerm]

    public static func detect(
        imageWidth: Int,
        imageHeight: Int,
        ocrResult: OCRResult,
        ocrAvailable: Bool,
        secureFieldFramesInScreenPoints: [CGRect],
        axAvailable: Bool,
        windowContentRectInScreenPoints: CGRect?,
        configuration: SensitiveDetectionConfiguration
    ) -> SensitiveDetectionOutcome {
        var regions: [RedactionRegion] = []
        var warnings: [String] = []
        var ocrGapOccurred = false
        var axGapOccurred = false

        let enabledOCRCategories = configuration.enabledCategories.intersection(ocrDerivedCategories)
        if !enabledOCRCategories.isEmpty {
            if ocrAvailable {
                for block in ocrResult.blocks {
                    let matches = SensitiveTextClassifier.matches(
                        in: block.text,
                        enabledCategories: enabledOCRCategories,
                        customTerms: configuration.customTerms,
                        customTermsCaseSensitive: configuration.customTermsCaseSensitive
                    )
                    guard let strongest = matches.max(by: { $0.confidence < $1.confidence }) else { continue }
                    guard let region = ocrRegion(for: block, match: strongest, imageWidth: imageWidth, imageHeight: imageHeight, style: configuration.style) else { continue }
                    regions.append(region)
                }
            } else {
                ocrGapOccurred = true
                warnings.append(
                    "Automatic text-based sensitive content detection did not complete for this capture; review the image before sharing."
                )
            }
        }

        if configuration.enabledCategories.contains(.secureField), let contentRect = windowContentRectInScreenPoints {
            if axAvailable {
                for frame in secureFieldFramesInScreenPoints {
                    guard let region = axRegion(for: frame, contentRect: contentRect, style: configuration.style) else { continue }
                    regions.append(region)
                }
            } else {
                axGapOccurred = true
                warnings.append(
                    "Accessibility permission is unavailable; secure text fields could not be checked for this capture."
                )
            }
        }

        let completeness: DetectionCompleteness = ocrGapOccurred ? .unavailable : (axGapOccurred ? .partiallyIncomplete : .complete)
        return SensitiveDetectionOutcome(regions: regions, completeness: completeness, warnings: warnings)
    }

    private static func ocrRegion(
        for block: RecognizedTextBlock,
        match: ClassifiedTextMatch,
        imageWidth: Int,
        imageHeight: Int,
        style: RedactionStyle
    ) -> RedactionRegion? {
        let pixelRect = RedactionCoordinateMapper.imagePixelRect(
            forVisionNormalizedBox: block.normalizedBoundingBox.cgRect,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
        let padded = RedactionCoordinateMapper.padded(pixelRect, byPixels: paddingPixels(for: match.category))
        let normalized = RedactionCoordinateMapper.normalizedRect(forImagePixelRect: padded, imageWidth: imageWidth, imageHeight: imageHeight)
        let clamped = RedactionCoordinateMapper.clampedToUnitSquare(normalized)
        guard clamped.width > 0, clamped.height > 0 else { return nil }
        return RedactionRegion(
            normalizedRect: CGRectDTO(clamped),
            category: match.category,
            confidence: match.confidence,
            source: .visionOCR,
            style: style
        )
    }

    private static func axRegion(for frame: CGRect, contentRect: CGRect, style: RedactionStyle) -> RedactionRegion? {
        guard let normalized = RedactionCoordinateMapper.normalizedRect(
            forElementFrameInScreenPoints: frame,
            windowContentRectInScreenPoints: contentRect
        ) else { return nil }
        let clamped = RedactionCoordinateMapper.clampedToUnitSquare(normalized)
        guard clamped.width > 0, clamped.height > 0 else { return nil }
        return RedactionRegion(
            normalizedRect: CGRectDTO(clamped),
            category: .secureField,
            confidence: 1.0,
            source: .accessibility,
            style: style
        )
    }
}

// MARK: - CaptureRedacting conformer

/// The redactor `CaptureCoordinator` injects into the main
/// `CaptureArtifactProcessor` pipeline. It composes manual regions (WP4,
/// unchanged) with WP5's automatic AX + Vision detection, merges them, and
/// applies the same flatten-before-persist contract `ManualRedactionPolicyRedactor`
/// established — this type supersedes it for every capture routed through
/// `CaptureArtifactProcessor`. `ManualRedactionPolicyRedactor` itself is
/// untouched and remains in use for Save As, which does not run automatic
/// detection (see `CaptureCoordinator`).
///
/// `suggest` and `required` both flatten immediately when any region (manual
/// or automatic) exists: WP5 does not add an interactive preview/confirm
/// step for automatically detected regions (no such UI is in this work
/// package's file list), so treating a detected region as pre-confirmed and
/// flattening it is the safer failure direction — over-redacting rather than
/// silently leaving a detected-but-unaddressed region in a "reviewed" image.
/// This is a deliberate, documented simplification versus the spec's
/// "preview regions; the user confirms" language in section 1, to be
/// revisited alongside a detected-region review UI.
public struct SensitiveContentPolicyRedactor: CaptureRedacting {
    private let renderer: RedactionRenderer
    private let secureFieldProvider: any SecureFieldFrameProviding
    /// `async` because the real provider (`RedactionSettings.shared`) is
    /// `@MainActor`; snapshotting it here — inside the redact call, off the
    /// main actor — keeps `CaptureArtifactProcessor`'s existing
    /// off-MainActor concurrency model intact instead of forcing every
    /// caller onto MainActor just to read settings.
    private let configurationProvider: @Sendable () async -> SensitiveDetectionConfiguration

    public init(
        renderer: RedactionRenderer = RedactionRenderer(),
        secureFieldProvider: any SecureFieldFrameProviding = AXSecureFieldFrameProvider(),
        configurationProvider: @escaping @Sendable () async -> SensitiveDetectionConfiguration
    ) {
        self.renderer = renderer
        self.secureFieldProvider = secureFieldProvider
        self.configurationProvider = configurationProvider
    }

    public func redact(_ image: CGImage, context: CaptureContext, ocrResult: OCRResult, ocrStatus: OCRStatus) async throws -> RedactedCaptureImage {
        switch context.redactionPolicy {
        case .none:
            return RedactedCaptureImage(image: image, status: .notRequested)
        case .suggest, .required:
            return try await detectAndFlatten(image, context: context, ocrResult: ocrResult, ocrStatus: ocrStatus)
        }
    }

    private func detectAndFlatten(_ image: CGImage, context: CaptureContext, ocrResult: OCRResult, ocrStatus: OCRStatus) async throws -> RedactedCaptureImage {
        let configuration = await configurationProvider()

        let axAvailable = secureFieldProvider.isAccessibilityTrusted
        var secureFieldFrames: [CGRect] = []
        if configuration.enabledCategories.contains(.secureField),
           let processID = context.processID,
           context.windowContentRectInScreenPoints != nil,
           axAvailable {
            secureFieldFrames = secureFieldProvider.secureFieldFrames(processID: processID)
        }

        let outcome = SensitiveContentDetector.detect(
            imageWidth: image.width,
            imageHeight: image.height,
            ocrResult: ocrResult,
            ocrAvailable: ocrStatus == .extracted,
            secureFieldFramesInScreenPoints: secureFieldFrames,
            axAvailable: axAvailable,
            windowContentRectInScreenPoints: context.windowContentRectInScreenPoints?.cgRect,
            configuration: configuration
        )

        let allRegions = RedactionRegionMerger.merge(context.manualRedactionRegions + outcome.regions)

        if !allRegions.isEmpty {
            let flattened = try renderer.flatten(image, regions: allRegions)
            return RedactedCaptureImage(image: flattened, status: .applied, regionCount: allRegions.count)
        }

        switch context.redactionPolicy {
        case .required:
            // Detection found nothing to flatten. If it did not fully
            // complete, "required" must not silently expose the raw image —
            // fail closed exactly as WP4's manual-only redactor did.
            guard outcome.completeness == .complete else {
                throw RedactionRequiredError.noReviewedRegion
            }
            return RedactedCaptureImage(image: image, status: .clean)
        case .suggest:
            switch outcome.completeness {
            case .complete:
                return RedactedCaptureImage(image: image, status: .clean)
            case .partiallyIncomplete:
                return RedactedCaptureImage(image: image, status: .needsReview, warnings: outcome.warnings)
            case .unavailable:
                return RedactedCaptureImage(image: image, status: .unavailable, warnings: outcome.warnings)
            }
        case .none:
            // Unreachable: `.none` is handled in `redact(_:context:ocrResult:ocrStatus:)`.
            return RedactedCaptureImage(image: image, status: .notRequested)
        }
    }
}
