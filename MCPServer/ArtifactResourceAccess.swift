import Foundation
import BerryShotIPC

/// Parses/builds the opaque resource URIs from `05-mcp-server-contract.md`
/// section 6: `berryshot://captures/{capture_id}/image|manifest|ocr`. This
/// is the *only* place the helper turns client-supplied text into a
/// `capture_id`; the id itself is still independently validated as a UUID
/// (`ArtifactPathContainment.validatedArtifactID`) before it is ever used —
/// this parser only rejects the surrounding URI shape.
enum ArtifactResourceURI {
    static let scheme = "berryshot"

    static func build(captureID: String, kind: ArtifactResourceKind) -> String {
        "berryshot://captures/\(captureID)/\(kind.rawValue)"
    }

    /// Returns `nil` for anything that is not exactly
    /// `berryshot://captures/<non-empty>/<image|manifest|ocr>` — an unknown
    /// scheme/host, missing/extra path components, or an unrecognized kind
    /// segment.
    static func parse(_ uriString: String) -> (captureID: String, kind: ArtifactResourceKind)? {
        guard let components = URLComponents(string: uriString),
              components.scheme == scheme,
              components.host == "captures" else {
            return nil
        }
        let pathParts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard pathParts.count == 2,
              let kind = ArtifactResourceKind(rawValue: String(pathParts[1])) else {
            return nil
        }
        let captureID = String(pathParts[0])
        guard !captureID.isEmpty else { return nil }
        return (captureID, kind)
    }
}

enum ArtifactResourceAccessError: Error, Sendable {
    case containmentViolation
    case readFailed
}

/// Reads a broker-resolved artifact file directly from disk, independently
/// re-verifying containment first (`02-target-architecture.md` section 4:
/// "helper verifies canonical containment before reading") rather than
/// trusting `ArtifactResourceLocationDTO.path` just because it came from
/// the broker.
enum ArtifactResourceAccess {
    static func expectedArtifactsRoot(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent("Artifacts", isDirectory: true)
    }

    static func readData(_ location: ArtifactResourceLocationDTO, expectedRoot: URL) throws -> Data {
        guard let contained = ArtifactPathContainment.canonicalContainedPath(location.path, withinRoot: expectedRoot.path) else {
            throw ArtifactResourceAccessError.containmentViolation
        }
        guard let data = FileManager.default.contents(atPath: contained) else {
            throw ArtifactResourceAccessError.readFailed
        }
        return data
    }
}
