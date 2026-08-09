import XCTest
@testable import BerryShotIPC

/// Wire-format round-trip tests for the WP8 `BrokerOperation`/`BrokerResult`
/// cases and DTOs, mirroring `BrokerEnvelopeCodableTests`. These exist
/// because `BrokerOperation`/`BrokerResult` use hand-written `Codable`
/// (`BrokerOperation.swift`'s doc comment: "written by hand rather than
/// relying on Swift's automatic enum-with-associated-values synthesis") —
/// a missed case in the `Kind` switch would compile but silently corrupt
/// that one operation/result on the wire, so every new case needs its own
/// explicit round-trip proof.
final class DocumentationAutomationCodableTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let farFutureDeadline = Date(timeIntervalSince1970: 1_800_000_000)

    private func roundTrip(_ operation: BrokerOperation) throws {
        let request = BrokerRequest(deadline: farFutureDeadline, sessionToken: "token123", operation: operation)
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(BrokerRequest.self, from: data)
        XCTAssertEqual(decoded, request)
    }

    private func roundTrip(_ result: BrokerResult) throws {
        let response = BrokerResponse.success(requestID: UUID(), result: result)
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(BrokerResponse.self, from: data)
        XCTAssertEqual(decoded, response)
    }

    // MARK: - Operations

    func testDocumentationSessionBeginRequestRoundTrips() throws {
        try roundTrip(.documentationSessionBegin(DocumentationSessionBeginRequest(
            bundleIdentifier: "com.example.App", displayName: "Test session", mode: .interactive,
            redactionPolicy: .required, redactionStyle: .solid, ttlSeconds: 1800, maxArtifacts: 20, allowLaunch: true
        )))
    }

    func testDocumentationSessionBeginRequestWithNilRedactionPolicyRoundTrips() throws {
        try roundTrip(.documentationSessionBegin(DocumentationSessionBeginRequest(
            bundleIdentifier: "com.example.App", displayName: "Test session", mode: .readOnly,
            redactionPolicy: nil, redactionStyle: .blur, ttlSeconds: 600, maxArtifacts: 5, allowLaunch: false
        )))
    }

    func testDocumentationSessionStatusRequestRoundTrips() throws {
        try roundTrip(.documentationSessionStatus(DocumentationSessionStatusRequest(sessionID: "abc123")))
    }

    func testDocumentationSessionCaptureStepRequestRoundTrips() throws {
        try roundTrip(.documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest(
            sessionID: "abc123", windowID: 7, feature: "General settings",
            navigationSummary: ["Settings", "General"], verification: .conditional, notes: ["Needs manual review"], ocr: true
        )))
    }

    func testDocumentationSessionEndRequestRoundTrips() throws {
        try roundTrip(.documentationSessionEnd(DocumentationSessionEndRequest(sessionID: "abc123")))
    }

    func testLaunchApplicationRequestRoundTrips() throws {
        try roundTrip(.launchApplication(LaunchApplicationRequest(sessionID: "abc123", approve: true)))
    }

    func testActivateApplicationRequestRoundTrips() throws {
        try roundTrip(.activateApplication(ActivateApplicationRequest(sessionID: "abc123")))
    }

    func testInspectUIRequestRoundTrips() throws {
        try roundTrip(.inspectUI(InspectUIRequest(sessionID: "abc123", elementRef: "ref-1", maxDepth: 4, maxNodes: 100)))
    }

    func testInspectUIRequestWithNilElementRefRoundTrips() throws {
        try roundTrip(.inspectUI(InspectUIRequest(sessionID: "abc123", elementRef: nil, maxDepth: 4, maxNodes: 100)))
    }

    func testPerformUIActionRequestRoundTripsForEveryActionKind() throws {
        for action in UIActionKind.allCases {
            try roundTrip(.performUIAction(PerformUIActionRequest(sessionID: "abc123", elementRef: "ref-1", action: action, value: action == .setValue ? "hello" : nil)))
        }
    }

    func testWaitForUIRequestRoundTripsForEveryPredicateKind() throws {
        for predicate in WaitPredicateKind.allCases {
            try roundTrip(.waitForUI(WaitForUIRequest(
                sessionID: "abc123", predicate: predicate, roleQuery: "AXButton", titleQuery: "Save",
                elementRef: "ref-1", expectedBool: true, timeoutMilliseconds: 5000
            )))
        }
    }

    // MARK: - Results

    func testDocumentationSessionResultRoundTrips() throws {
        let dto = DocumentationSessionDTO(
            sessionID: "abc123", bundleIdentifier: "com.example.App", displayName: "Test", mode: .interactive, status: .active,
            startedAt: "2026-01-01T00:00:00Z", expiresAt: "2026-01-01T01:00:00Z", allowLaunch: true,
            redactionPolicy: .required, redactionStyle: .solid, maxArtifacts: 20, artifactCount: 1,
            lastActionAt: "2026-01-01T00:05:00Z", lastActionDescription: "Inspected UI",
            steps: [DocumentationStepDTO(stepID: "s1", feature: "F1", captureIDs: ["c1"], navigationSummary: ["Main"], redactionStatus: .applied, verification: .verified, notes: [], recordedAt: "2026-01-01T00:05:00Z")],
            coverage: DocumentationCoverageDTO(verified: ["s1"], conditional: [], blocked: [], notAttempted: [])
        )
        try roundTrip(.documentationSession(dto))
    }

    func testApplicationLaunchResultRoundTrips() throws {
        try roundTrip(.applicationLaunch(ApplicationLaunchResultDTO(bundleIdentifier: "com.example.App", processID: 100, wasAlreadyRunning: false, isActive: true)))
    }

    func testUISnapshotResultRoundTrips() throws {
        let node = AXNodeDTO(
            ref: "ref-1", role: "AXButton", subrole: nil, title: "Save", descriptionText: nil,
            enabledState: true, focused: false, frame: AXFrameDTO(x: 0, y: 0, width: 100, height: 30),
            actions: [.press], childCount: 0, children: []
        )
        let snapshot = UISnapshotDTO(sessionID: "abc123", bundleIdentifier: "com.example.App", processID: 100, generation: 1, windowTitle: "Window", root: node, truncatedByDepth: false, truncatedByNodeCount: false)
        try roundTrip(.uiSnapshot(snapshot))
    }

    func testUIActionResultRoundTrips() throws {
        try roundTrip(.uiActionResult(UIActionResultDTO(sessionID: "abc123", elementRef: "ref-1", action: .press, performed: true, role: "AXButton")))
    }

    func testUIWaitResultRoundTrips() throws {
        try roundTrip(.uiWaitResult(UIWaitResultDTO(sessionID: "abc123", satisfied: true, timedOut: false, elapsedMilliseconds: 42)))
    }

    // MARK: - Error codes

    func testAllWP8ErrorCodesRoundTripThroughRawValue() throws {
        let expected: [BrokerErrorCode: String] = [
            .sessionNotFound: "session_not_found",
            .sessionExpired: "session_expired",
            .sessionStopped: "session_stopped",
            .bundleNotAllowed: "bundle_not_allowed",
            .artifactLimitReached: "artifact_limit_reached",
            .elementStale: "element_stale",
            .actionBlocked: "action_blocked",
            .launchNotApproved: "launch_not_approved",
            .applicationNotRunning: "application_not_running"
        ]
        for (code, rawValue) in expected {
            XCTAssertEqual(code.rawValue, rawValue)
        }
    }

    func testDocumentationCoverageStateRawValues() throws {
        XCTAssertEqual(DocumentationCoverageState.verified.rawValue, "verified")
        XCTAssertEqual(DocumentationCoverageState.conditional.rawValue, "conditional")
        XCTAssertEqual(DocumentationCoverageState.blocked.rawValue, "blocked")
        XCTAssertEqual(DocumentationCoverageState.notAttempted.rawValue, "not_attempted")
    }
}
