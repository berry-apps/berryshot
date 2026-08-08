import Foundation
import CryptoKit
import BerryShotIPC

/// The `ArtifactStore` from `02-target-architecture.md`'s process topology
/// diagram: "PNG + manifest + TTL". Owns a private, per-capture directory
/// under `~/Library/Application Support/BerryShot/MCP/Artifacts/<uuid>/`
/// containing `image.png`, `manifest.json`, and an optional `ocr.txt`.
///
/// Contract obligations this type is responsible for
/// (`05-mcp-server-contract.md` sections 6 and 7,
/// `08-implementation-work-packages.md` WP7 task 3):
///
/// - Opaque IDs: every artifact is keyed by a freshly generated `UUID`;
///   nothing here ever accepts a client-supplied path.
/// - Canonical path containment: every returned path is re-validated
///   against ``rootDirectory`` via `ArtifactPathContainment` immediately
///   before being handed out, and a requested capture ID is rejected unless
///   it parses as a bare UUID (`ArtifactPathContainment.validatedArtifactID`)
///   *before* it is ever interpolated into a path.
/// - Content hashes: `sha256` in the manifest is computed from the exact
///   final PNG bytes this type writes.
/// - TTL/quota eviction: `ttl`/`quotaBytes`/`maxArtifacts` default to the
///   locked values in `10-decisions-risks-open-questions.md` section 4
///   ("24-hour TTL, 500 MiB quota, and 200 retained artifacts with
///   expired-then-LRU eviction").
/// - Immutable manifest: `manifest.json` is written once, atomically, and
///   never rewritten.
/// - Leases so cleanup cannot delete a file mid-read: see `resolve(...)`'s
///   doc comment for the bounded, auto-expiring lease this actor grants.
/// - OCR resource publication is disabled by default: `ocr.txt` is written
///   only when the caller explicitly opts in (`ocr: true` on the capture
///   tool), matching "OCR resource publication is disabled by default even
///   when OCR runs internally for redaction."
public actor CaptureArtifactStore {
    public enum StoreError: Error, Sendable, Equatable {
        /// The capture ID does not parse as a UUID at all — never even
        /// looked up.
        case malformedID
        case notFound
        case expired
        /// The kind exists conceptually but was never published for this
        /// capture (OCR not requested, or a manifest/image write raced a
        /// failure — see `store(...)`).
        case notPublished
        case writeFailed
    }

    public static let defaultTTL: TimeInterval = 24 * 60 * 60
    public static let defaultQuotaBytes: Int = 500 * 1024 * 1024
    public static let defaultMaxArtifacts: Int = 200
    /// How long a `resolve(...)` lease survives before auto-expiring if the
    /// caller never comes back. See `resolve(...)`'s doc comment.
    public static let defaultLeaseAutoExpirySeconds: TimeInterval = 10

    public static var defaultRootDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BerryShot", isDirectory: true)
            .appendingPathComponent("MCP", isDirectory: true)
            .appendingPathComponent("Artifacts", isDirectory: true)
    }

    private struct Record {
        var manifest: CaptureManifestDTO
        let imagePath: String
        let manifestPath: String
        var ocrPath: String?
        let imageByteCount: Int
        let createdAt: Date
        var lastAccessedAt: Date
        var leaseCount: Int = 0
    }

    public let rootDirectory: URL
    private let ttl: TimeInterval
    private let quotaBytes: Int
    private let maxArtifacts: Int
    private let leaseAutoExpirySeconds: TimeInterval

    private var records: [String: Record] = [:]
    /// Insertion order, oldest first — a simple, sufficient tie-breaker;
    /// eviction itself sorts by `lastAccessedAt`, not this array's order.
    private var insertionOrder: [String] = []

    public init(
        rootDirectory: URL = CaptureArtifactStore.defaultRootDirectory,
        ttl: TimeInterval = CaptureArtifactStore.defaultTTL,
        quotaBytes: Int = CaptureArtifactStore.defaultQuotaBytes,
        maxArtifacts: Int = CaptureArtifactStore.defaultMaxArtifacts,
        leaseAutoExpirySeconds: TimeInterval = CaptureArtifactStore.defaultLeaseAutoExpirySeconds
    ) {
        self.rootDirectory = rootDirectory
        self.ttl = ttl
        self.quotaBytes = quotaBytes
        self.maxArtifacts = maxArtifacts
        self.leaseAutoExpirySeconds = leaseAutoExpirySeconds
    }

    // MARK: - Write path

    /// Persists one already-redacted final PNG plus its manifest, evicts if
    /// over budget, and returns the immutable manifest. `ocrText` is
    /// written to `ocr.txt` only when non-nil (the caller's own decision
    /// about whether OCR publication was requested — see
    /// `LiveCaptureBrokerCaptureOperations`).
    public func store(
        imageData: Data,
        ocrText: String?,
        bundleIdentifier: String,
        processID: Int32,
        windowID: UInt32,
        windowTitle: String,
        pixelWidth: Int,
        pixelHeight: Int,
        pointPixelScale: Double,
        redactionStatus: IPCRedactionStatus,
        redactionRegionCount: Int,
        warnings: [String]
    ) throws -> CaptureManifestDTO {
        let id = UUID().uuidString
        let directory = rootDirectory.appendingPathComponent(id, isDirectory: true)
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootDirectory.path)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw StoreError.writeFailed
        }

        let imagePath = directory.appendingPathComponent("image.png").path
        let manifestPath = directory.appendingPathComponent("manifest.json").path
        var ocrPath: String?

        guard fileManager.createFile(atPath: imagePath, contents: imageData, attributes: [.posixPermissions: 0o600]) else {
            try? fileManager.removeItem(at: directory)
            throw StoreError.writeFailed
        }
        if let ocrText {
            let path = directory.appendingPathComponent("ocr.txt").path
            guard fileManager.createFile(atPath: path, contents: Data(ocrText.utf8), attributes: [.posixPermissions: 0o600]) else {
                try? fileManager.removeItem(at: directory)
                throw StoreError.writeFailed
            }
            ocrPath = path
        }

        let sha256 = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        let createdAt = Date()
        let manifest = CaptureManifestDTO(
            captureID: id,
            resourceURI: "berryshot://captures/\(id)/image",
            manifestURI: "berryshot://captures/\(id)/manifest",
            ocrURI: ocrPath != nil ? "berryshot://captures/\(id)/ocr" : nil,
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            windowID: windowID,
            windowTitle: windowTitle,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            pointPixelScale: pointPixelScale,
            redactionStatus: redactionStatus,
            redactionRegionCount: redactionRegionCount,
            ocrAvailable: ocrPath != nil,
            sha256: sha256,
            createdAt: ISO8601DateFormatter().string(from: createdAt),
            warnings: warnings
        )

        do {
            let manifestData = try JSONEncoder().encode(manifest)
            guard fileManager.createFile(atPath: manifestPath, contents: manifestData, attributes: [.posixPermissions: 0o600]) else {
                throw StoreError.writeFailed
            }
        } catch {
            try? fileManager.removeItem(at: directory)
            throw StoreError.writeFailed
        }

        records[id] = Record(
            manifest: manifest,
            imagePath: imagePath,
            manifestPath: manifestPath,
            ocrPath: ocrPath,
            imageByteCount: imageData.count,
            createdAt: createdAt,
            lastAccessedAt: createdAt
        )
        insertionOrder.append(id)

        evictIfNeeded()
        return manifest
    }

    // MARK: - Read path

    public func manifest(captureID: String) throws -> CaptureManifestDTO {
        try record(for: captureID).manifest
    }

    /// Resolves `captureID`/`kind` to a broker-issued, already-contained
    /// absolute path and grants a short-lived lease that prevents
    /// `evictIfNeeded()` from deleting the underlying file for
    /// ``leaseAutoExpirySeconds`` (`05-mcp-server-contract.md` section 6:
    /// "Active resource reads hold a lease so cleanup cannot delete the
    /// file mid-read"). The lease auto-expires rather than requiring an
    /// explicit release call: the only reader is the same-machine
    /// `BerryShotMCP` helper, which reads the file within milliseconds of
    /// this call returning, so a bounded expiry both satisfies the
    /// "cannot delete mid-read" requirement and guarantees the lease can
    /// never leak forever if the helper crashes or never comes back.
    public func resolve(captureID: String, kind: ArtifactResourceKind) throws -> ArtifactResourceLocationDTO {
        let record = try record(for: captureID)
        let path: String
        let mimeType: String
        switch kind {
        case .image:
            path = record.imagePath
            mimeType = "image/png"
        case .manifest:
            path = record.manifestPath
            mimeType = "application/json"
        case .ocr:
            guard let ocrPath = record.ocrPath else { throw StoreError.notPublished }
            path = ocrPath
            mimeType = "text/plain"
        }

        guard let contained = ArtifactPathContainment.canonicalContainedPath(path, withinRoot: rootDirectory.path) else {
            // Never expected in production (every path above was built from
            // `rootDirectory` moments earlier by `store(...)`), but this is
            // the store's own last line of defense, matching the same
            // containment check the helper independently repeats.
            throw StoreError.writeFailed
        }

        takeLease(captureID)
        touch(captureID)
        return ArtifactResourceLocationDTO(path: contained, mimeType: mimeType)
    }

    // MARK: - Lookup/eviction internals

    private func record(for rawID: String) throws -> Record {
        guard let id = ArtifactPathContainment.validatedArtifactID(rawID) else {
            throw StoreError.malformedID
        }
        guard var record = records[id] else {
            throw StoreError.notFound
        }
        guard Date().timeIntervalSince(record.createdAt) <= ttl else {
            remove(id)
            throw StoreError.expired
        }
        record.lastAccessedAt = Date()
        records[id] = record
        return record
    }

    private func touch(_ id: String) {
        guard var record = records[id] else { return }
        record.lastAccessedAt = Date()
        records[id] = record
    }

    private func takeLease(_ id: String) {
        guard records[id] != nil else { return }
        records[id]?.leaseCount += 1
        let expiry = leaseAutoExpirySeconds
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, expiry) * 1_000_000_000))
            await self?.releaseLease(id)
        }
    }

    private func releaseLease(_ id: String) {
        guard var record = records[id] else { return }
        record.leaseCount = max(0, record.leaseCount - 1)
        records[id] = record
    }

    private func isLeased(_ id: String) -> Bool {
        (records[id]?.leaseCount ?? 0) > 0
    }

    private func totalBytes() -> Int {
        records.values.reduce(0) { $0 + $1.imageByteCount }
    }

    /// Expired-first, then least-recently-accessed-immutable-artifact
    /// eviction (`05-mcp-server-contract.md` section 6). Never removes a
    /// leased artifact.
    private func evictIfNeeded() {
        let now = Date()
        for id in insertionOrder where !isLeased(id) {
            if let record = records[id], now.timeIntervalSince(record.createdAt) > ttl {
                remove(id)
            }
        }

        while totalBytes() > quotaBytes || records.count > maxArtifacts {
            let candidates = insertionOrder.filter { !isLeased($0) }
            guard let lruID = candidates.min(by: { (records[$0]?.lastAccessedAt ?? .distantPast) < (records[$1]?.lastAccessedAt ?? .distantPast) }) else {
                // Everything remaining is leased; defer eviction to the
                // next call rather than deleting a file being read.
                break
            }
            remove(lruID)
        }
    }

    private func remove(_ id: String) {
        guard let record = records.removeValue(forKey: id) else { return }
        insertionOrder.removeAll { $0 == id }
        let directory = (record.imagePath as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: directory)
    }

    // MARK: - Test-only introspection

    /// Exposed only so tests can assert eviction/lease behavior without
    /// racing real TTL/wall-clock timing.
    var artifactCount: Int { records.count }
    func debugIsLeased(_ id: String) -> Bool { isLeased(id) }
}
