import XCTest
import CryptoKit
@testable import BerryShot
import BerryShotIPC

final class CaptureArtifactStoreTests: XCTestCase {
    private var rootDirectory: URL!

    override func setUp() {
        super.setUp()
        rootDirectory = URL(fileURLWithPath: "/tmp/bsartifacts-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: rootDirectory)
        rootDirectory = nil
        super.tearDown()
    }

    private func makeStore(ttl: TimeInterval = CaptureArtifactStore.defaultTTL, quotaBytes: Int = CaptureArtifactStore.defaultQuotaBytes, maxArtifacts: Int = CaptureArtifactStore.defaultMaxArtifacts, leaseAutoExpirySeconds: TimeInterval = 5) -> CaptureArtifactStore {
        CaptureArtifactStore(rootDirectory: rootDirectory, ttl: ttl, quotaBytes: quotaBytes, maxArtifacts: maxArtifacts, leaseAutoExpirySeconds: leaseAutoExpirySeconds)
    }

    private func storeSample(_ store: CaptureArtifactStore, imageData: Data = Data("fake-png-bytes".utf8), ocrText: String? = nil, windowID: UInt32 = 42) async throws -> CaptureManifestDTO {
        try await store.store(
            imageData: imageData,
            ocrText: ocrText,
            bundleIdentifier: "com.example.App",
            processID: 100,
            windowID: windowID,
            windowTitle: "Untitled",
            pixelWidth: 800,
            pixelHeight: 600,
            pointPixelScale: 2.0,
            redactionStatus: .applied,
            redactionRegionCount: 2,
            warnings: []
        )
    }

    // MARK: - Write path

    func testStoreWritesImageAndManifestFilesAndComputesSha256() async throws {
        let store = makeStore()
        let imageData = Data("fake-png-bytes".utf8)
        let manifest = try await storeSample(store, imageData: imageData)

        let expectedHash = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(manifest.sha256, expectedHash)
        XCTAssertEqual(manifest.bundleIdentifier, "com.example.App")
        XCTAssertEqual(manifest.windowID, 42)
        XCTAssertEqual(manifest.redactionRegionCount, 2)
        XCTAssertFalse(manifest.ocrAvailable)
        XCTAssertNil(manifest.ocrURI)
        XCTAssertEqual(manifest.resourceURI, "berryshot://captures/\(manifest.captureID)/image")
        XCTAssertEqual(manifest.manifestURI, "berryshot://captures/\(manifest.captureID)/manifest")

        // Opaque ID: never a filesystem path.
        XCTAssertNotNil(UUID(uuidString: manifest.captureID))
    }

    func testOCRTextIsPersistedOnlyWhenProvided() async throws {
        let store = makeStore()
        let published = try await storeSample(store, ocrText: "hello world")
        XCTAssertTrue(published.ocrAvailable)
        XCTAssertEqual(published.ocrURI, "berryshot://captures/\(published.captureID)/ocr")

        let notPublished = try await storeSample(store, ocrText: nil, windowID: 43)
        XCTAssertFalse(notPublished.ocrAvailable)
        XCTAssertNil(notPublished.ocrURI)
    }

    // MARK: - Resolve / read path

    func testResolveImageReturnsContainedPathUnderRootWithPNGMimeType() async throws {
        let store = makeStore()
        let manifest = try await storeSample(store)
        let location = try await store.resolve(captureID: manifest.captureID, kind: .image)
        XCTAssertTrue(location.path.hasPrefix(rootDirectory.resolvingSymlinksInPath().path))
        XCTAssertEqual(location.mimeType, "image/png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path))
    }

    func testResolveManifestAndOCRUseTheirOwnMimeTypes() async throws {
        let store = makeStore()
        let manifest = try await storeSample(store, ocrText: "some text")
        let manifestLocation = try await store.resolve(captureID: manifest.captureID, kind: .manifest)
        XCTAssertEqual(manifestLocation.mimeType, "application/json")
        let ocrLocation = try await store.resolve(captureID: manifest.captureID, kind: .ocr)
        XCTAssertEqual(ocrLocation.mimeType, "text/plain")
        let ocrText = try String(contentsOfFile: ocrLocation.path, encoding: .utf8)
        XCTAssertEqual(ocrText, "some text")
    }

    func testResolveOCRWhenNotPublishedThrowsNotPublished() async throws {
        let store = makeStore()
        let manifest = try await storeSample(store, ocrText: nil)
        do {
            _ = try await store.resolve(captureID: manifest.captureID, kind: .ocr)
            XCTFail("Expected .notPublished")
        } catch CaptureArtifactStore.StoreError.notPublished {
            // expected
        }
    }

    // MARK: - Opaque ID validation / path traversal

    func testMalformedCaptureIDIsRejectedBeforeAnyLookup() async throws {
        let store = makeStore()
        let attempts = ["not-a-uuid", "../../../../etc/passwd", "", "  ", String(repeating: "a", count: 5000)]
        for attempt in attempts {
            do {
                _ = try await store.manifest(captureID: attempt)
                XCTFail("Expected .malformedID for \(attempt)")
            } catch CaptureArtifactStore.StoreError.malformedID {
                // expected
            }
        }
    }

    func testUnknownButWellFormedCaptureIDIsNotFound() async throws {
        let store = makeStore()
        do {
            _ = try await store.manifest(captureID: UUID().uuidString)
            XCTFail("Expected .notFound")
        } catch CaptureArtifactStore.StoreError.notFound {
            // expected
        }
    }

    func testResolvedPathsAlwaysPassContainmentCheckAgainstRoot() async throws {
        let store = makeStore()
        let manifest = try await storeSample(store)
        let location = try await store.resolve(captureID: manifest.captureID, kind: .image)
        let contained = ArtifactPathContainment.canonicalContainedPath(location.path, withinRoot: rootDirectory.path)
        XCTAssertNotNil(contained, "every path the store hands out must be contained within its own root")
    }

    // MARK: - TTL expiry

    func testExpiredArtifactIsRejectedAndRemovedFromDisk() async throws {
        let store = makeStore(ttl: 0.05)
        let manifest = try await storeSample(store)
        let location = try await store.resolve(captureID: manifest.captureID, kind: .image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path))

        try await Task.sleep(nanoseconds: 150_000_000)

        do {
            _ = try await store.manifest(captureID: manifest.captureID)
            XCTFail("Expected .expired")
        } catch CaptureArtifactStore.StoreError.expired {
            // expected
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path), "an expired artifact's files must be removed")
    }

    // MARK: - Quota / count eviction

    func testMaxArtifactsEvictsOldestByLastAccessOnceOverTheBound() async throws {
        let store = makeStore(maxArtifacts: 2)
        let first = try await storeSample(store, windowID: 1)
        _ = try await storeSample(store, windowID: 2)
        _ = try await storeSample(store, windowID: 3)

        let count = await store.artifactCount
        XCTAssertLessThanOrEqual(count, 2)
        do {
            _ = try await store.manifest(captureID: first.captureID)
            XCTFail("Expected the oldest, least-recently-accessed artifact to have been evicted")
        } catch CaptureArtifactStore.StoreError.notFound {
            // expected
        }
    }

    func testQuotaBytesEvictsLeastRecentlyAccessedFirst() async throws {
        // Each artifact is ~1000 bytes; a 1500-byte quota only ever allows one to survive at a time.
        let store = makeStore(quotaBytes: 1500)
        let bigPayload = Data(repeating: 0x41, count: 1000)
        let first = try await storeSample(store, imageData: bigPayload, windowID: 1)
        _ = try await storeSample(store, imageData: bigPayload, windowID: 2)

        do {
            _ = try await store.manifest(captureID: first.captureID)
            XCTFail("Expected the first artifact to be evicted once the quota was exceeded")
        } catch CaptureArtifactStore.StoreError.notFound {
            // expected
        }
    }

    func testAccessingAnArtifactUpdatesRecencySoItSurvivesOverAnUntouchedOne() async throws {
        let store = makeStore(maxArtifacts: 2)
        let first = try await storeSample(store, windowID: 1)
        let second = try await storeSample(store, windowID: 2)

        // Touch `first` so it becomes more recently accessed than `second`.
        _ = try await store.manifest(captureID: first.captureID)

        _ = try await storeSample(store, windowID: 3) // pushes the store over maxArtifacts

        // `second` was never touched after being created before `first`'s
        // access bump, so it should be the one evicted, not `first`.
        do {
            _ = try await store.manifest(captureID: second.captureID)
            XCTFail("Expected the untouched artifact to be evicted")
        } catch CaptureArtifactStore.StoreError.notFound {
            // expected
        }
        _ = try await store.manifest(captureID: first.captureID) // must still exist
    }

    // MARK: - Lease protects against mid-read eviction

    func testLeasedArtifactSurvivesAnEvictionSweepUntilTheLeaseExpires() async throws {
        let store = makeStore(maxArtifacts: 1, leaseAutoExpirySeconds: 2)
        let leased = try await storeSample(store, windowID: 1)
        // Resolving takes a lease on `leased`.
        _ = try await store.resolve(captureID: leased.captureID, kind: .image)

        // Storing a second artifact would normally evict the oldest to stay
        // within maxArtifacts: 1, but `leased` is currently leased.
        _ = try await storeSample(store, windowID: 2)

        // The leased artifact must still be resolvable/on-disk despite being over the bound.
        let stillThere = try? await store.manifest(captureID: leased.captureID)
        XCTAssertNotNil(stillThere, "a leased artifact must not be evicted while its lease is held")
    }

    // MARK: - Idle-with-quota: never keeps unbounded artifacts on repeated captures

    func testRepeatedCapturesDoNotGrowArtifactCountWithoutBound() async throws {
        let store = makeStore(maxArtifacts: 5)
        for index in 0..<20 {
            _ = try await storeSample(store, windowID: UInt32(index))
        }
        let count = await store.artifactCount
        XCTAssertLessThanOrEqual(count, 5)
    }
}
