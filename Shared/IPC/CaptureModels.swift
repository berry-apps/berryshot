import Foundation

/// WP7 wire-level mirrors of the `BerryShot`-target redaction enums
/// (`Sources/Redaction/RedactionModels.swift`, `Sources/Capture/CaptureContext.swift`,
/// `Sources/Capture/CaptureArtifact.swift`). `BerryShotIPC` has zero
/// dependencies (`Package.swift`) and cannot import `BerryShot` — that
/// dependency runs the other way — so these are intentionally independent
/// types with matching cases, exactly like WP6's `ApplicationSummaryDTO`/
/// `WindowSummaryDTO` already stand in for `ApplicationDescriptor`/
/// `WindowDescriptor`. `CaptureBroker` (in the `BerryShot` target, which
/// already depends on `BerryShotIPC`) converts between them.
public enum IPCRedactionPolicy: String, Codable, Sendable, Equatable {
    case none
    case suggest
    case required
}

public enum IPCRedactionStyle: String, Codable, Sendable, Equatable {
    case blur
    case pixelate
    case solid
}

public enum IPCRedactionStatus: String, Codable, Sendable, Equatable {
    case notRequested
    case clean
    case applied
    case needsReview
    case unavailable
}

public enum IPCApplicationWindowPolicy: String, Codable, Sendable, Equatable {
    case frontmostWindow
    case allOnScreenWindows
}

/// The three artifact resource kinds `05-mcp-server-contract.md` section 6
/// defines: `berryshot://captures/{id}/image|manifest|ocr`.
public enum ArtifactResourceKind: String, Codable, Sendable, Equatable {
    case image
    case manifest
    case ocr
}

// MARK: - capture_window

public struct CaptureWindowRequest: Codable, Sendable, Equatable {
    public let windowID: UInt32
    public let expectedBundleIdentifier: String
    public let redactionPolicy: IPCRedactionPolicy
    public let redactionStyle: IPCRedactionStyle
    public let ocr: Bool
    public let previewMaxEdge: Int

    public init(
        windowID: UInt32,
        expectedBundleIdentifier: String,
        redactionPolicy: IPCRedactionPolicy,
        redactionStyle: IPCRedactionStyle,
        ocr: Bool,
        previewMaxEdge: Int
    ) {
        self.windowID = windowID
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.redactionPolicy = redactionPolicy
        self.redactionStyle = redactionStyle
        self.ocr = ocr
        self.previewMaxEdge = previewMaxEdge
    }
}

/// The immutable, sanitized capture manifest. This exact shape is returned
/// three ways per `05-mcp-server-contract.md`: as `capture_window`/
/// `capture_application`'s structured metadata, as `get_capture_manifest`'s
/// result, and as the `berryshot://captures/{id}/manifest` resource body —
/// so all three stay byte-for-byte consistent by construction instead of by
/// convention. Field names/`CodingKeys` are pinned to the exact snake_case
/// keys the contract's section 5 example shows (`capture_id`, `bundle_id`,
/// `window_id`, `pixel_width`, `point_pixel_scale`, `ocr_available`, ...);
/// this is the one DTO in this file whose JSON shape *is* the public,
/// contract-pinned shape (unlike WP6's `PermissionsStatusDTO`/
/// `ApplicationSummaryDTO`/`WindowSummaryDTO`, which used ordinary
/// camelCase Codable synthesis and left external casing "a WP7 concern" —
/// see those types' updated doc comments). It never carries a raw
/// filesystem path (`05-mcp-server-contract.md` section 3: "It never
/// reveals raw filesystem paths").
public struct CaptureManifestDTO: Codable, Sendable, Equatable {
    public let captureID: String
    public let resourceURI: String
    public let manifestURI: String
    public let ocrURI: String?
    public let bundleIdentifier: String
    public let processID: Int32
    public let windowID: UInt32
    public let windowTitle: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let pointPixelScale: Double
    public let redactionStatus: IPCRedactionStatus
    public let redactionRegionCount: Int
    public let ocrAvailable: Bool
    public let sha256: String
    /// RFC 3339 / ISO 8601, pre-formatted at manifest-creation time rather
    /// than left to an encoder's `dateEncodingStrategy` — this DTO's JSON
    /// shape must stay identical no matter which `JSONEncoder` instance
    /// happens to encode it (internal IPC vs. the MCP tool-result path),
    /// and a `Date` value's wire representation would otherwise silently
    /// depend on that choice.
    public let createdAt: String
    public let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case captureID = "capture_id"
        case resourceURI = "resource_uri"
        case manifestURI = "manifest_uri"
        case ocrURI = "ocr_uri"
        case bundleIdentifier = "bundle_id"
        case processID = "process_id"
        case windowID = "window_id"
        case windowTitle = "window_title"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
        case pointPixelScale = "point_pixel_scale"
        case redactionStatus = "redaction_status"
        case redactionRegionCount = "redaction_region_count"
        case ocrAvailable = "ocr_available"
        case sha256
        case createdAt = "created_at"
        case warnings
    }

    public init(
        captureID: String,
        resourceURI: String,
        manifestURI: String,
        ocrURI: String?,
        bundleIdentifier: String,
        processID: Int32,
        windowID: UInt32,
        windowTitle: String,
        pixelWidth: Int,
        pixelHeight: Int,
        pointPixelScale: Double,
        redactionStatus: IPCRedactionStatus,
        redactionRegionCount: Int,
        ocrAvailable: Bool,
        sha256: String,
        createdAt: String,
        warnings: [String]
    ) {
        self.captureID = captureID
        self.resourceURI = resourceURI
        self.manifestURI = manifestURI
        self.ocrURI = ocrURI
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.windowID = windowID
        self.windowTitle = windowTitle
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointPixelScale = pointPixelScale
        self.redactionStatus = redactionStatus
        self.redactionRegionCount = redactionRegionCount
        self.ocrAvailable = ocrAvailable
        self.sha256 = sha256
        self.createdAt = createdAt
        self.warnings = warnings
    }
}

// MARK: - get_capture_manifest

public struct GetCaptureManifestRequest: Codable, Sendable, Equatable {
    public let captureID: String

    public init(captureID: String) {
        self.captureID = captureID
    }
}

// MARK: - Artifact resource resolution (used for image/manifest/ocr reads)

public struct ResolveArtifactResourceRequest: Codable, Sendable, Equatable {
    public let captureID: String
    public let kind: ArtifactResourceKind

    public init(captureID: String, kind: ArtifactResourceKind) {
        self.captureID = captureID
        self.kind = kind
    }
}

/// A broker-issued, already-contained absolute path plus the MIME type the
/// helper should serve it as. `05-mcp-server-contract.md` section 7: "Broker
/// returns an artifact ID and broker-issued contained path; helper verifies
/// containment before reading" — `ArtifactPathContainment` is the shared
/// verification the helper independently re-runs on `path` before opening
/// it, rather than trusting the broker blindly.
public struct ArtifactResourceLocationDTO: Codable, Sendable, Equatable {
    public let path: String
    public let mimeType: String

    public init(path: String, mimeType: String) {
        self.path = path
        self.mimeType = mimeType
    }
}
