import XCTest
@testable import BerryShot
import BerryShotIPC

private struct FakeCaptureWindowDiscovery: CaptureBrokerDiscovering {
    var windows: [WindowDescriptor] = []
    func discoverApplications() async throws -> [ApplicationDescriptor] { [] }
    func discoverWindows() async throws -> [WindowDescriptor] { windows }
}

private struct FakePermissions: CaptureBrokerPermissionsChecking {
    var screenCapture: Bool
    func screenCaptureGranted() -> Bool { screenCapture }
    func accessibilityGranted() -> Bool { true }
}

private struct FakeCaptureOperations: CaptureBrokerCaptureOperating {
    var manifest: CaptureManifestDTO?
    var errorToThrow: Error?
    /// Records the `WindowDescriptor` `CaptureBroker` actually resolved and
    /// handed off, so tests can assert the broker matched by `window_id`
    /// and not, say, always passing through the first discovered window.
    let matchedWindowBox: MatchedWindowBox

    func captureWindow(_ request: CaptureWindowRequest, matchedWindow: WindowDescriptor) async throws -> CaptureManifestDTO {
        await matchedWindowBox.set(matchedWindow)
        if let errorToThrow { throw errorToThrow }
        return manifest ?? sampleManifest(windowID: matchedWindow.id, bundleIdentifier: matchedWindow.bundleIdentifier)
    }
}

private actor MatchedWindowBox {
    var window: WindowDescriptor?
    func set(_ window: WindowDescriptor) { self.window = window }
}

private func sampleManifest(windowID: UInt32 = 7, bundleIdentifier: String = "com.example.App", captureID: String = UUID().uuidString) -> CaptureManifestDTO {
    CaptureManifestDTO(
        captureID: captureID,
        resourceURI: "berryshot://captures/\(captureID)/image",
        manifestURI: "berryshot://captures/\(captureID)/manifest",
        ocrURI: nil,
        bundleIdentifier: bundleIdentifier,
        processID: 100,
        windowID: windowID,
        windowTitle: "Window",
        pixelWidth: 800,
        pixelHeight: 600,
        pointPixelScale: 2.0,
        redactionStatus: .applied,
        redactionRegionCount: 1,
        ocrAvailable: false,
        sha256: "deadbeef",
        createdAt: ISO8601DateFormatter().string(from: Date()),
        warnings: []
    )
}

private func makeWindow(id: UInt32, bundleIdentifier: String) -> WindowDescriptor {
    WindowDescriptor(
        id: id, bundleIdentifier: bundleIdentifier, applicationName: "Example", processID: 100,
        title: "Window", frameInScreenPoints: CGRectDTO(x: 0, y: 0, width: 400, height: 300), isOnScreen: true
    )
}

private let farFutureDeadline = Date().addingTimeInterval(60)

final class CaptureBrokerCaptureWindowTests: XCTestCase {
    private var rootDirectory: URL!

    override func setUp() {
        super.setUp()
        rootDirectory = URL(fileURLWithPath: "/tmp/bsbrokercap-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: rootDirectory)
        rootDirectory = nil
        super.tearDown()
    }

    private func makeBroker(
        windows: [WindowDescriptor] = [],
        screenCaptureGranted: Bool = true,
        captureOperations: FakeCaptureOperations = FakeCaptureOperations(matchedWindowBox: MatchedWindowBox())
    ) -> CaptureBroker {
        CaptureBroker(
            discovery: FakeCaptureWindowDiscovery(windows: windows),
            permissions: FakePermissions(screenCapture: screenCaptureGranted),
            artifactStore: CaptureArtifactStore(rootDirectory: rootDirectory),
            captureOperations: captureOperations
        )
    }

    // MARK: - Identity / staleness validation (the broker's own responsibility)

    func testStaleWindowIDIsRejectedWithWindowNotAvailable() async throws {
        let broker = makeBroker(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.App")])
        let request = CaptureWindowRequest(windowID: 999, expectedBundleIdentifier: "com.example.App", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        do {
            _ = try await broker.submit(.captureWindow(request), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected window_not_available")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .windowNotAvailable)
        }
    }

    func testBundleMismatchIsRejectedWithWindowIdentityChanged() async throws {
        let broker = makeBroker(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.Actual")])
        let request = CaptureWindowRequest(windowID: 1, expectedBundleIdentifier: "com.example.Expected", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        do {
            _ = try await broker.submit(.captureWindow(request), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected window_identity_changed")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .windowIdentityChanged)
        }
    }

    func testMatchingWindowIsHandedOffToCaptureOperationsExactly() async throws {
        let box = MatchedWindowBox()
        let operations = FakeCaptureOperations(matchedWindowBox: box)
        let broker = makeBroker(windows: [makeWindow(id: 5, bundleIdentifier: "com.example.App")], captureOperations: operations)
        let request = CaptureWindowRequest(windowID: 5, expectedBundleIdentifier: "com.example.App", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        _ = try await broker.submit(.captureWindow(request), requestID: UUID(), deadline: farFutureDeadline)
        let matched = await box.window
        XCTAssertEqual(matched?.id, 5)
        XCTAssertEqual(matched?.bundleIdentifier, "com.example.App")
    }

    // MARK: - Permission gate

    func testScreenRecordingNotGrantedIsRejectedBeforeAnyDiscoveryOrCapture() async throws {
        let broker = makeBroker(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.App")], screenCaptureGranted: false)
        let request = CaptureWindowRequest(windowID: 1, expectedBundleIdentifier: "com.example.App", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        do {
            _ = try await broker.submit(.captureWindow(request), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected permission_denied")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .permissionDenied)
        }
    }

    // MARK: - Argument bounds re-validated at the broker (not just the helper)

    func testEmptyExpectedBundleIDIsRejected() async throws {
        let broker = makeBroker(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.App")])
        let request = CaptureWindowRequest(windowID: 1, expectedBundleIdentifier: "", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 960)
        do {
            _ = try await broker.submit(.captureWindow(request), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }

    func testPreviewMaxEdgeBelowMinimumIsRejected() async throws {
        let broker = makeBroker(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.App")])
        let request = CaptureWindowRequest(windowID: 1, expectedBundleIdentifier: "com.example.App", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 100)
        do {
            _ = try await broker.submit(.captureWindow(request), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }

    func testPreviewMaxEdgeAboveMaximumIsRejected() async throws {
        let broker = makeBroker(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.App")])
        let request = CaptureWindowRequest(windowID: 1, expectedBundleIdentifier: "com.example.App", redactionPolicy: .none, redactionStyle: .solid, ocr: false, previewMaxEdge: 5000)
        do {
            _ = try await broker.submit(.captureWindow(request), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }

    // MARK: - getCaptureManifest / resolveArtifactResource plumbing

    func testGetCaptureManifestReturnsWhatWasStored() async throws {
        let store = CaptureArtifactStore(rootDirectory: rootDirectory)
        let broker = CaptureBroker(discovery: FakeCaptureWindowDiscovery(), artifactStore: store)
        let manifest = try await store.store(
            imageData: Data("png".utf8), ocrText: nil, bundleIdentifier: "com.example.App", processID: 1,
            windowID: 1, windowTitle: "W", pixelWidth: 10, pixelHeight: 10, pointPixelScale: 1,
            redactionStatus: .clean, redactionRegionCount: 0, warnings: []
        )
        let result = try await broker.submit(.getCaptureManifest(GetCaptureManifestRequest(captureID: manifest.captureID)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .manifest(let returned) = result else { return XCTFail("Expected .manifest") }
        XCTAssertEqual(returned, manifest)
    }

    func testGetCaptureManifestForUnknownIDReturnsResourceNotFound() async throws {
        let broker = makeBroker()
        do {
            _ = try await broker.submit(.getCaptureManifest(GetCaptureManifestRequest(captureID: UUID().uuidString)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected resource_not_found")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .resourceNotFound)
        }
    }

    func testGetCaptureManifestForMalformedIDReturnsInvalidArgument() async throws {
        let broker = makeBroker()
        do {
            _ = try await broker.submit(.getCaptureManifest(GetCaptureManifestRequest(captureID: "../../etc/passwd")), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }

    func testResolveArtifactResourceForExpiredCaptureReturnsResourceExpired() async throws {
        let store = CaptureArtifactStore(rootDirectory: rootDirectory, ttl: 0.05)
        let broker = CaptureBroker(discovery: FakeCaptureWindowDiscovery(), artifactStore: store)
        let manifest = try await store.store(
            imageData: Data("png".utf8), ocrText: nil, bundleIdentifier: "com.example.App", processID: 1,
            windowID: 1, windowTitle: "W", pixelWidth: 10, pixelHeight: 10, pointPixelScale: 1,
            redactionStatus: .clean, redactionRegionCount: 0, warnings: []
        )
        try await Task.sleep(nanoseconds: 150_000_000)
        do {
            _ = try await broker.submit(.resolveArtifactResource(ResolveArtifactResourceRequest(captureID: manifest.captureID, kind: .image)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected resource_expired")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .resourceExpired)
        }
    }

    func testResolveArtifactResourceForUnpublishedOCRReturnsResourceNotFound() async throws {
        let store = CaptureArtifactStore(rootDirectory: rootDirectory)
        let broker = CaptureBroker(discovery: FakeCaptureWindowDiscovery(), artifactStore: store)
        let manifest = try await store.store(
            imageData: Data("png".utf8), ocrText: nil, bundleIdentifier: "com.example.App", processID: 1,
            windowID: 1, windowTitle: "W", pixelWidth: 10, pixelHeight: 10, pointPixelScale: 1,
            redactionStatus: .clean, redactionRegionCount: 0, warnings: []
        )
        do {
            _ = try await broker.submit(.resolveArtifactResource(ResolveArtifactResourceRequest(captureID: manifest.captureID, kind: .ocr)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected resource_not_found")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .resourceNotFound)
        }
    }
}
