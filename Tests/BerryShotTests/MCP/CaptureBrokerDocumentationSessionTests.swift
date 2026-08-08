import XCTest
@testable import BerryShot
import BerryShotIPC

private struct FakeDiscovery: CaptureBrokerDiscovering {
    var windows: [WindowDescriptor] = []
    func discoverApplications() async throws -> [ApplicationDescriptor] { [] }
    func discoverWindows() async throws -> [WindowDescriptor] { windows }
}

private struct FakePermissions: CaptureBrokerPermissionsChecking {
    var screenCapture: Bool = true
    func screenCaptureGranted() -> Bool { screenCapture }
    func accessibilityGranted() -> Bool { true }
}

private struct FakeCaptureOperations: CaptureBrokerCaptureOperating {
    var errorToThrow: Error?
    func captureWindow(_ request: CaptureWindowRequest, matchedWindow: WindowDescriptor) async throws -> CaptureManifestDTO {
        if let errorToThrow { throw errorToThrow }
        let captureID = UUID().uuidString
        return CaptureManifestDTO(
            captureID: captureID,
            resourceURI: "berryshot://captures/\(captureID)/image",
            manifestURI: "berryshot://captures/\(captureID)/manifest",
            ocrURI: nil,
            bundleIdentifier: matchedWindow.bundleIdentifier,
            processID: matchedWindow.processID,
            windowID: matchedWindow.id,
            windowTitle: matchedWindow.title,
            pixelWidth: 800,
            pixelHeight: 600,
            pointPixelScale: 2.0,
            redactionStatus: .applied,
            redactionRegionCount: 0,
            ocrAvailable: false,
            sha256: "deadbeef",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            warnings: []
        )
    }
}

private func makeWindow(id: UInt32, bundleIdentifier: String) -> WindowDescriptor {
    WindowDescriptor(
        id: id, bundleIdentifier: bundleIdentifier, applicationName: "Example", processID: 100,
        title: "Window", frameInScreenPoints: CGRectDTO(x: 0, y: 0, width: 400, height: 300), isOnScreen: true
    )
}

private let farFutureDeadline = Date().addingTimeInterval(60)

/// Broker-level tests for `documentation_session_begin/status/capture_step/end`
/// (`06-agent-documentation-security.md` section 2). The AX/launch-specific
/// security matrix (stale ref, secure field, blocked action, Stop-during-wait)
/// lives in `CaptureBrokerUIAutomationTests`; this file covers the
/// session-lifecycle and capture-step half.
final class CaptureBrokerDocumentationSessionTests: XCTestCase {
    private var rootDirectory: URL!

    override func setUp() {
        super.setUp()
        rootDirectory = URL(fileURLWithPath: "/tmp/bsdocsession-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: rootDirectory)
        rootDirectory = nil
        super.tearDown()
    }

    private func makeBroker(
        windows: [WindowDescriptor] = [],
        captureOperations: FakeCaptureOperations = FakeCaptureOperations()
    ) -> CaptureBroker {
        CaptureBroker(
            discovery: FakeDiscovery(windows: windows),
            permissions: FakePermissions(),
            artifactStore: CaptureArtifactStore(rootDirectory: rootDirectory),
            captureOperations: captureOperations
        )
    }

    // MARK: - begin / status

    func testBeginThenStatusRoundTrips() async throws {
        let broker = makeBroker()
        let beginResult = try await broker.submit(.documentationSessionBegin(makeSessionBeginRequest(bundleIdentifier: "com.example.App")), requestID: UUID(), deadline: farFutureDeadline)
        guard case .documentationSession(let begun) = beginResult else { return XCTFail("Expected .documentationSession") }
        XCTAssertEqual(begun.bundleIdentifier, "com.example.App")
        XCTAssertEqual(begun.status, .active)

        let statusResult = try await broker.submit(.documentationSessionStatus(DocumentationSessionStatusRequest(sessionID: begun.sessionID)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .documentationSession(let status) = statusResult else { return XCTFail("Expected .documentationSession") }
        XCTAssertEqual(status.sessionID, begun.sessionID)
    }

    func testStatusOfUnknownSessionReturnsSessionNotFound() async throws {
        let broker = makeBroker()
        do {
            _ = try await broker.submit(.documentationSessionStatus(DocumentationSessionStatusRequest(sessionID: "nonexistent")), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected session_not_found")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .sessionNotFound)
        }
    }

    func testBeginRejectsWeakerRedactionPolicyThroughTheBroker() async throws {
        let broker = makeBroker()
        let request = DocumentationSessionBeginRequest(
            bundleIdentifier: "com.example.App", displayName: "Test", mode: .readOnly,
            redactionPolicy: .suggest, redactionStyle: .solid, ttlSeconds: 600, maxArtifacts: 10, allowLaunch: false
        )
        do {
            _ = try await broker.submit(.documentationSessionBegin(request), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }

    // MARK: - capture_step: the "wrong bundle" security-matrix case

    func testCaptureStepSucceedsForWindowBelongingToSessionBundle() async throws {
        let broker = makeBroker(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.App")])
        let begin = try await beginSession(broker, bundleIdentifier: "com.example.App")

        let result = try await broker.submit(
            .documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest(sessionID: begin.sessionID, windowID: 1, feature: "General settings", navigationSummary: ["Settings"], verification: .verified, notes: [])),
            requestID: UUID(), deadline: farFutureDeadline
        )
        guard case .documentationSession(let updated) = result else { return XCTFail("Expected .documentationSession") }
        XCTAssertEqual(updated.artifactCount, 1)
        XCTAssertEqual(updated.steps.first?.verification, .verified)
        XCTAssertEqual(updated.coverage.verified.count, 1)
    }

    /// `06-agent-documentation-security.md` section 8: "Attempt action
    /// against a non-session bundle ID: rejected." A window that belongs to
    /// a *different* application than the session's allowlisted bundle must
    /// never be captured through this session, even though the caller only
    /// supplied a raw `window_id` (never a bundle id of their own — the
    /// broker independently discovers the window's real owner and compares
    /// it against the session).
    func testCaptureStepRejectsWindowBelongingToDifferentBundle() async throws {
        let broker = makeBroker(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.Other")])
        let begin = try await beginSession(broker, bundleIdentifier: "com.example.App")

        do {
            _ = try await broker.submit(
                .documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest(sessionID: begin.sessionID, windowID: 1, feature: "General settings", navigationSummary: [], verification: .verified, notes: [])),
                requestID: UUID(), deadline: farFutureDeadline
            )
            XCTFail("Expected bundle_not_allowed")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .bundleNotAllowed)
        }
    }

    func testCaptureStepRejectsUnknownWindowID() async throws {
        let broker = makeBroker(windows: [])
        let begin = try await beginSession(broker, bundleIdentifier: "com.example.App")
        do {
            _ = try await broker.submit(
                .documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest(sessionID: begin.sessionID, windowID: 999, feature: "F", navigationSummary: [], verification: .verified, notes: [])),
                requestID: UUID(), deadline: farFutureDeadline
            )
            XCTFail("Expected window_not_available")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .windowNotAvailable)
        }
    }

    func testCaptureStepUsesSessionRedactionPolicyNotAnyCallerValue() async throws {
        // `DocumentationSessionCaptureStepRequest` has no redaction fields
        // at all (see its doc comment) — this test proves the broker
        // actually threads the session's locked-in `.required`/style
        // through to the underlying `captureWindow` pipeline by inspecting
        // what `FakeCaptureOperations` was invoked with.
        actor CapturedRequestBox {
            var request: CaptureWindowRequest?
            func set(_ request: CaptureWindowRequest) { self.request = request }
        }
        let box = CapturedRequestBox()
        struct RecordingCaptureOperations: CaptureBrokerCaptureOperating {
            let box: CapturedRequestBox
            func captureWindow(_ request: CaptureWindowRequest, matchedWindow: WindowDescriptor) async throws -> CaptureManifestDTO {
                await box.set(request)
                let captureID = UUID().uuidString
                return CaptureManifestDTO(
                    captureID: captureID, resourceURI: "berryshot://captures/\(captureID)/image", manifestURI: "berryshot://captures/\(captureID)/manifest", ocrURI: nil,
                    bundleIdentifier: matchedWindow.bundleIdentifier, processID: matchedWindow.processID, windowID: matchedWindow.id, windowTitle: matchedWindow.title,
                    pixelWidth: 10, pixelHeight: 10, pointPixelScale: 2.0, redactionStatus: .applied, redactionRegionCount: 0, ocrAvailable: false,
                    sha256: "x", createdAt: ISO8601DateFormatter().string(from: Date()), warnings: []
                )
            }
        }

        let recordingBroker = CaptureBroker(
            discovery: FakeDiscovery(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.App")]),
            permissions: FakePermissions(),
            artifactStore: CaptureArtifactStore(rootDirectory: rootDirectory),
            captureOperations: RecordingCaptureOperations(box: box)
        )
        let begin = try await beginSession(recordingBroker, bundleIdentifier: "com.example.App")

        _ = try await recordingBroker.submit(
            .documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest(sessionID: begin.sessionID, windowID: 1, feature: "F", navigationSummary: [], verification: .verified, notes: [])),
            requestID: UUID(), deadline: farFutureDeadline
        )

        let captured = await box.request
        XCTAssertEqual(captured?.redactionPolicy, .required)
        XCTAssertEqual(captured?.expectedBundleIdentifier, "com.example.App")
    }

    // MARK: - artifact limit

    func testCaptureStepRejectsAtSessionArtifactLimit() async throws {
        let broker = makeBroker(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.App"), makeWindow(id: 2, bundleIdentifier: "com.example.App")])
        let begin = try await beginSession(broker, bundleIdentifier: "com.example.App", maxArtifacts: 1)

        _ = try await broker.submit(
            .documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest(sessionID: begin.sessionID, windowID: 1, feature: "F1", navigationSummary: [], verification: .verified, notes: [])),
            requestID: UUID(), deadline: farFutureDeadline
        )
        do {
            _ = try await broker.submit(
                .documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest(sessionID: begin.sessionID, windowID: 2, feature: "F2", navigationSummary: [], verification: .verified, notes: [])),
                requestID: UUID(), deadline: farFutureDeadline
            )
            XCTFail("Expected artifact_limit_reached")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .artifactLimitReached)
        }
    }

    // MARK: - end / Stop

    func testEndStopsSessionAndFurtherCaptureStepIsRejected() async throws {
        let broker = makeBroker(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.App")])
        let begin = try await beginSession(broker, bundleIdentifier: "com.example.App")

        let endResult = try await broker.submit(.documentationSessionEnd(DocumentationSessionEndRequest(sessionID: begin.sessionID)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .documentationSession(let ended) = endResult else { return XCTFail("Expected .documentationSession") }
        XCTAssertEqual(ended.status, .stopped)

        do {
            _ = try await broker.submit(
                .documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest(sessionID: begin.sessionID, windowID: 1, feature: "F", navigationSummary: [], verification: .verified, notes: [])),
                requestID: UUID(), deadline: farFutureDeadline
            )
            XCTFail("Expected session_stopped")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .sessionStopped)
        }
    }

    /// `cancelAll()` (the broker-wide Stop the GUI's Privacy toggle/off
    /// switch triggers — see `BrokerIPCServer.stop()`) must also stop every
    /// active documentation session, not only drain the request queue.
    func testCancelAllStopsEveryActiveDocumentationSession() async throws {
        let broker = makeBroker()
        let begin = try await beginSession(broker, bundleIdentifier: "com.example.App")
        await broker.cancelAll()

        // `cancelAll` fires the stop asynchronously (`Task { await
        // sessionManager.stopAll() }`); give it a moment before asserting.
        try await Task.sleep(nanoseconds: 100_000_000)

        do {
            _ = try await broker.submit(.documentationSessionStatus(DocumentationSessionStatusRequest(sessionID: begin.sessionID)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected session_stopped")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .sessionStopped)
        }
    }

    // MARK: - helpers

    @discardableResult
    private func beginSession(_ broker: CaptureBroker, bundleIdentifier: String, maxArtifacts: Int = 20) async throws -> DocumentationSessionDTO {
        let result = try await broker.submit(.documentationSessionBegin(makeSessionBeginRequest(bundleIdentifier: bundleIdentifier, maxArtifacts: maxArtifacts)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .documentationSession(let dto) = result else {
            XCTFail("Expected .documentationSession")
            throw BrokerOperationError(code: .internalError, message: "test setup failed")
        }
        return dto
    }
}
