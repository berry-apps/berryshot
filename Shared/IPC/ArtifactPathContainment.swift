import Foundation

/// Canonical path-containment check shared by the artifact store (GUI side,
/// which only ever constructs paths under its own root, but still checks
/// its own output as a last line of defense) and the MCP helper (which
/// independently re-verifies a broker-issued path before opening it —
/// `02-target-architecture.md` section 4: "Broker-issued opaque artifact
/// IDs; helper verifies canonical containment before reading").
///
/// This is deliberately the *only* place either process decides whether a
/// path is "inside the artifact store": callers never accept a client- or
/// broker-supplied path without running it through here first.
public enum ArtifactPathContainment {
    /// Returns the canonicalized absolute path if `path` resolves to
    /// somewhere inside `root` (after resolving `.`/`..`/symlinks), or
    /// `nil` if it does not. Neither a request-controlled ID (already
    /// constrained to a bare UUID before it ever reaches a path — see
    /// `CaptureArtifactStore`) nor a broker bug can escape the artifact
    /// store this way.
    public static func canonicalContainedPath(_ path: String, withinRoot root: String) -> String? {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath()
        let candidateURL = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()

        let rootPath = rootURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let candidatePath = candidateURL.path

        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPrefix) else { return nil }
        return candidatePath
    }

    /// Strict opaque-ID validation: a capture ID must be exactly a
    /// lowercase-or-uppercase UUID string. This runs *before* the ID is
    /// ever interpolated into a path component, so `../`, absolute paths,
    /// symlink names, and null bytes are rejected by construction rather
    /// than relying solely on the containment check above to catch them
    /// after the fact.
    public static func validatedArtifactID(_ raw: String) -> String? {
        guard let uuid = UUID(uuidString: raw) else { return nil }
        // Re-derive from the parsed UUID (not the caller's raw string) so
        // the value used to build a path is always exactly 36 canonical
        // characters, regardless of what casing/whitespace the input had.
        return uuid.uuidString
    }
}
