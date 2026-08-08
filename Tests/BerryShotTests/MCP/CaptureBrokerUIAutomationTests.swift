import XCTest
@testable import BerryShot
import BerryShotIPC

private struct UIAutomationEmptyDiscovery: CaptureBrokerDiscovering {
    var windows: [WindowDescriptor] = []
    func discoverApplications() async throws -> [ApplicationDescriptor] { [] }
    func discoverWindows() async throws -> [WindowDescriptor] { windows }
}

private func makeWindowFixture(id: UInt32, bundleIdentifier: String) -> WindowDescriptor {
    WindowDescriptor(
        id: id, bundleIdentifier: bundleIdentifier, applicationName: "Example", processID: 100,
        title: "Window \(id)", frameInScreenPoints: CGRectDTO(x: 0, y: 0, width: 400, height: 300), isOnScreen: true
    )
}

private struct FakeCaptureOperations: CaptureBrokerCaptureOperating {
    func captureWindow(_ request: CaptureWindowRequest, matchedWindow: WindowDescriptor) async throws -> CaptureManifestDTO {
        let captureID = UUID().uuidString
        return CaptureManifestDTO(
            captureID: captureID, resourceURI: "berryshot://captures/\(captureID)/image", manifestURI: "berryshot://captures/\(captureID)/manifest", ocrURI: nil,
            bundleIdentifier: matchedWindow.bundleIdentifier, processID: matchedWindow.processID, windowID: matchedWindow.id, windowTitle: matchedWindow.title,
            pixelWidth: 10, pixelHeight: 10, pointPixelScale: 2.0, redactionStatus: .applied, redactionRegionCount: 0, ocrAvailable: false,
            sha256: "x", createdAt: ISO8601DateFormatter().string(from: Date()), warnings: []
        )
    }
}

private let farFutureDeadline = Date().addingTimeInterval(60)

/// The WP8 security matrix (`06-agent-documentation-security.md` section 8's
/// verification checklist), exercised end-to-end through `CaptureBroker`
/// with `FakeAXInspecting`/`FakeApplicationLaunching` standing in for real
/// Accessibility/`NSWorkspace` calls — the same fake-the-OS-boundary
/// pattern `CaptureBrokerTests`/`CaptureBrokerCaptureWindowTests` already
/// use for ScreenCaptureKit:
///
/// - wrong bundle rejected -> `CaptureBrokerDocumentationSessionTests`
/// - stale element ref rejected -> below
/// - secure field access rejected -> below
/// - blocked action rejected -> below
/// - Stop kills session work promptly -> below
///
/// plus the sample-safe-app coverage test and custom-canvas conditional/
/// blocked test from `08-implementation-work-packages.md` WP8's
/// verification section.
final class CaptureBrokerUIAutomationTests: XCTestCase {
    private var rootDirectory: URL!
    private var axInspecting: FakeAXInspecting!
    private var applicationLaunching: FakeApplicationLaunching!

    override func setUp() {
        super.setUp()
        rootDirectory = URL(fileURLWithPath: "/tmp/bsuiautomation-\(UUID().uuidString.prefix(8))", isDirectory: true)
        axInspecting = FakeAXInspecting()
        applicationLaunching = FakeApplicationLaunching()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: rootDirectory)
        rootDirectory = nil
        axInspecting = nil
        applicationLaunching = nil
        super.tearDown()
    }

    private func makeBroker(windows: [WindowDescriptor] = []) -> CaptureBroker {
        CaptureBroker(
            discovery: UIAutomationEmptyDiscovery(windows: windows),
            artifactStore: CaptureArtifactStore(rootDirectory: rootDirectory),
            captureOperations: FakeCaptureOperations(),
            axInspecting: axInspecting,
            applicationLaunching: applicationLaunching
        )
    }

    @discardableResult
    private func beginSession(_ broker: CaptureBroker, bundleIdentifier: String = "com.example.SafeApp", allowLaunch: Bool = false) async throws -> DocumentationSessionDTO {
        let result = try await broker.submit(.documentationSessionBegin(makeSessionBeginRequest(bundleIdentifier: bundleIdentifier, allowLaunch: allowLaunch)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .documentationSession(let dto) = result else {
            XCTFail("Expected .documentationSession")
            throw BrokerOperationError(code: .internalError, message: "test setup failed")
        }
        return dto
    }

    // MARK: - launch_application

    func testLaunchApplicationRejectsWithoutSessionAllowLaunch() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker, allowLaunch: false)
        do {
            _ = try await broker.submit(.launchApplication(LaunchApplicationRequest(sessionID: session.sessionID, approve: true)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected launch_not_approved")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .launchNotApproved)
        }
    }

    func testLaunchApplicationRejectsWithoutPerCallApproval() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker, allowLaunch: true)
        do {
            _ = try await broker.submit(.launchApplication(LaunchApplicationRequest(sessionID: session.sessionID, approve: false)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected launch_not_approved")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .launchNotApproved)
        }
    }

    func testLaunchApplicationSucceedsWithBothGates() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker, allowLaunch: true)
        let result = try await broker.submit(.launchApplication(LaunchApplicationRequest(sessionID: session.sessionID, approve: true)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .applicationLaunch(let launch) = result else { return XCTFail("Expected .applicationLaunch") }
        XCTAssertEqual(launch.bundleIdentifier, session.bundleIdentifier)
        XCTAssertFalse(launch.wasAlreadyRunning)
        XCTAssertTrue(launch.isActive)
        XCTAssertEqual(applicationLaunching.launchCallCount(), 1)
    }

    /// `LaunchApplicationRequest` has no `bundle_id` field at all — the only
    /// bundle identifier `ApplicationLaunching.launch` is ever called with
    /// is the session's, by construction.
    func testLaunchApplicationOnlyEverTargetsSessionBundle() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker, bundleIdentifier: "com.example.OnlyThisOne", allowLaunch: true)
        _ = try await broker.submit(.launchApplication(LaunchApplicationRequest(sessionID: session.sessionID, approve: true)), requestID: UUID(), deadline: farFutureDeadline)
        XCTAssertNotNil(applicationLaunching.runningProcessID(bundleIdentifier: "com.example.OnlyThisOne"))
    }

    // MARK: - activate_application

    func testActivateApplicationRejectsWhenNotRunning() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        do {
            _ = try await broker.submit(.activateApplication(ActivateApplicationRequest(sessionID: session.sessionID)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected application_not_running")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .applicationNotRunning)
        }
    }

    func testActivateApplicationSucceedsWhenRunning() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        applicationLaunching.setRunning(bundleIdentifier: session.bundleIdentifier, pid: 4242)
        let result = try await broker.submit(.activateApplication(ActivateApplicationRequest(sessionID: session.sessionID)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .applicationLaunch(let launch) = result else { return XCTFail("Expected .applicationLaunch") }
        XCTAssertEqual(launch.processID, 4242)
        XCTAssertTrue(launch.isActive)
    }

    // MARK: - inspect_ui

    func testInspectUIRejectsWhenApplicationNotRunning() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        do {
            _ = try await broker.submit(.inspectUI(InspectUIRequest(sessionID: session.sessionID, maxDepth: 4, maxNodes: 100)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected application_not_running")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .applicationNotRunning)
        }
    }

    func testInspectUIReturnsBoundedSnapshotWithRefs() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker, bundleIdentifier: "com.example.SafeApp")
        applicationLaunching.setRunning(bundleIdentifier: session.bundleIdentifier, pid: 100)
        axInspecting.setWindow(pid: 100, title: "Sample Safe App", root: makeSampleSafeAppWindow())

        let result = try await broker.submit(.inspectUI(InspectUIRequest(sessionID: session.sessionID, maxDepth: 6, maxNodes: 100)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .uiSnapshot(let snapshot) = result else { return XCTFail("Expected .uiSnapshot") }
        XCTAssertEqual(snapshot.processID, 100)
        XCTAssertEqual(snapshot.generation, 1)
        XCTAssertEqual(snapshot.root.children.count, 5)
        XCTAssertNotNil(snapshot.root.ref)
    }

    func testInspectUIRejectsOutOfBoundsDepthAndNodeCount() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        applicationLaunching.setRunning(bundleIdentifier: session.bundleIdentifier, pid: 100)
        axInspecting.setWindow(pid: 100, title: "App", root: makeSampleSafeAppWindow())

        do {
            _ = try await broker.submit(.inspectUI(InspectUIRequest(sessionID: session.sessionID, maxDepth: 0, maxNodes: 100)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument for max_depth")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
        do {
            _ = try await broker.submit(.inspectUI(InspectUIRequest(sessionID: session.sessionID, maxDepth: 4, maxNodes: 10_000)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument for max_nodes")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }

    // MARK: - perform_ui_action: the security matrix

    @discardableResult
    private func inspectSampleSafeApp(_ broker: CaptureBroker, session: DocumentationSessionDTO, pid: Int32 = 100) async throws -> UISnapshotDTO {
        applicationLaunching.setRunning(bundleIdentifier: session.bundleIdentifier, pid: pid)
        axInspecting.setWindow(pid: pid, title: "Sample Safe App", root: makeSampleSafeAppWindow())
        let result = try await broker.submit(.inspectUI(InspectUIRequest(sessionID: session.sessionID, maxDepth: 6, maxNodes: 100)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .uiSnapshot(let snapshot) = result else { throw BrokerOperationError(code: .internalError, message: "test setup failed") }
        return snapshot
    }

    private func findRef(_ snapshot: UISnapshotDTO, title: String) -> String? {
        findNode(snapshot.root, title: title)?.ref
    }

    private func findNode(_ node: AXNodeDTO, title: String) -> AXNodeDTO? {
        if node.title == title { return node }
        for child in node.children {
            if let found = findNode(child, title: title) { return found }
        }
        return nil
    }

    func testPerformUIActionSucceedsForAllowlistedPressAction() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        let snapshot = try await inspectSampleSafeApp(broker, session: session)
        let saveRef = try XCTUnwrap(findRef(snapshot, title: "Save"))

        let result = try await broker.submit(.performUIAction(PerformUIActionRequest(sessionID: session.sessionID, elementRef: saveRef, action: .press)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .uiActionResult(let actionResult) = result else { return XCTFail("Expected .uiActionResult") }
        XCTAssertTrue(actionResult.performed)
        XCTAssertEqual(axInspecting.actionsPerformed().count, 1)
    }

    func testPerformUIActionSucceedsForSetValueOnOrdinaryTextField() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        let snapshot = try await inspectSampleSafeApp(broker, session: session)
        let searchRef = try XCTUnwrap(findRef(snapshot, title: "Search"))

        let result = try await broker.submit(.performUIAction(PerformUIActionRequest(sessionID: session.sessionID, elementRef: searchRef, action: .setValue, value: "invoices")), requestID: UUID(), deadline: farFutureDeadline)
        guard case .uiActionResult(let actionResult) = result else { return XCTFail("Expected .uiActionResult") }
        XCTAssertTrue(actionResult.performed)
        let performed = axInspecting.actionsPerformed()
        XCTAssertEqual(performed.count, 1)
        XCTAssertEqual(performed.first?.value, "invoices")
    }

    /// `06-agent-documentation-security.md` section 8: "Reuse stale element
    /// reference after PID/window change: rejected."
    func testPerformUIActionRejectsStaleElementRefAfterReInspect() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        let snapshot = try await inspectSampleSafeApp(broker, session: session)
        let staleRef = try XCTUnwrap(findRef(snapshot, title: "Save"))

        // A second inspect_ui call (as an agent would do after navigating)
        // bumps the generation and invalidates every ref from the first call.
        _ = try await broker.submit(.inspectUI(InspectUIRequest(sessionID: session.sessionID, maxDepth: 6, maxNodes: 100)), requestID: UUID(), deadline: farFutureDeadline)

        do {
            _ = try await broker.submit(.performUIAction(PerformUIActionRequest(sessionID: session.sessionID, elementRef: staleRef, action: .press)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected element_stale")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .elementStale)
        }
        XCTAssertEqual(axInspecting.actionsPerformed().count, 0, "the stale ref must never reach performAction")
    }

    func testPerformUIActionRejectsUnknownElementRef() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        _ = try await inspectSampleSafeApp(broker, session: session)
        do {
            _ = try await broker.submit(.performUIAction(PerformUIActionRequest(sessionID: session.sessionID, elementRef: "forged-ref-that-was-never-issued", action: .press)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected element_stale")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .elementStale)
        }
    }

    /// `06-agent-documentation-security.md` section 8: "Attempt value
    /// read/write on secure field: rejected and no plaintext in log."
    func testPerformUIActionRejectsSetValueOnSecureField() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        let snapshot = try await inspectSampleSafeApp(broker, session: session)
        let passwordRef = try XCTUnwrap(findRef(snapshot, title: "Password"))
        let passwordNode = try XCTUnwrap(findNode(snapshot.root, title: "Password"))
        XCTAssertTrue(passwordNode.actions.isEmpty, "a secure field must never advertise any action in the snapshot itself")

        do {
            _ = try await broker.submit(.performUIAction(PerformUIActionRequest(sessionID: session.sessionID, elementRef: passwordRef, action: .setValue, value: "hunter2")), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected action_blocked")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .actionBlocked)
        }
        XCTAssertEqual(axInspecting.actionsPerformed().count, 0, "a secure field's value must never reach the AX layer, let alone a log")
    }

    /// `06-agent-documentation-security.md` section 8: "Attempt blocked
    /// role/action such as Delete/Buy/Send: rejected."
    func testPerformUIActionRejectsDestructiveButtonEvenThoughAXWouldAllowPress() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        let snapshot = try await inspectSampleSafeApp(broker, session: session)
        let deleteRef = try XCTUnwrap(findRef(snapshot, title: "Delete Account"))

        do {
            _ = try await broker.submit(.performUIAction(PerformUIActionRequest(sessionID: session.sessionID, elementRef: deleteRef, action: .press)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected action_blocked")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .actionBlocked)
        }
        XCTAssertEqual(axInspecting.actionsPerformed().count, 0)
    }

    func testPerformUIActionRejectsActionNotAdvertisedForElement() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        let snapshot = try await inspectSampleSafeApp(broker, session: session)
        // "Enable Notifications" only advertises `.press`, never `.increment`.
        let toggleRef = try XCTUnwrap(findRef(snapshot, title: "Enable Notifications"))

        do {
            _ = try await broker.submit(.performUIAction(PerformUIActionRequest(sessionID: session.sessionID, elementRef: toggleRef, action: .increment)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected action_blocked")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .actionBlocked)
        }
    }

    /// A ref minted under one session must never resolve for a different
    /// session, even against the same broker/registry instance.
    func testPerformUIActionRejectsRefFromADifferentSession() async throws {
        let broker = makeBroker()
        let sessionA = try await beginSession(broker, bundleIdentifier: "com.example.AppA")
        let snapshotA = try await inspectSampleSafeApp(broker, session: sessionA, pid: 100)
        let refA = try XCTUnwrap(findRef(snapshotA, title: "Save"))

        let sessionB = try await beginSession(broker, bundleIdentifier: "com.example.AppB")
        applicationLaunching.setRunning(bundleIdentifier: sessionB.bundleIdentifier, pid: 200)
        axInspecting.setWindow(pid: 200, title: "App B", root: FakeAXNode(id: "b-root", role: "AXWindow", children: []))

        do {
            _ = try await broker.submit(.performUIAction(PerformUIActionRequest(sessionID: sessionB.sessionID, elementRef: refA, action: .press)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected element_stale")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .elementStale)
        }
    }

    // MARK: - wait_for_ui

    func testWaitForUIReturnsSatisfiedImmediatelyWhenPredicateAlreadyTrue() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        applicationLaunching.setRunning(bundleIdentifier: session.bundleIdentifier, pid: 100)
        axInspecting.setWindow(pid: 100, title: "Sample Safe App", root: makeSampleSafeAppWindow())

        let result = try await broker.submit(
            .waitForUI(WaitForUIRequest(sessionID: session.sessionID, predicate: .elementAppears, roleQuery: nil, titleQuery: "Save", timeoutMilliseconds: 2000)),
            requestID: UUID(), deadline: farFutureDeadline
        )
        guard case .uiWaitResult(let waitResult) = result else { return XCTFail("Expected .uiWaitResult") }
        XCTAssertTrue(waitResult.satisfied)
        XCTAssertFalse(waitResult.timedOut)
    }

    func testWaitForUITimesOutWhenPredicateNeverSatisfied() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        applicationLaunching.setRunning(bundleIdentifier: session.bundleIdentifier, pid: 100)
        axInspecting.setWindow(pid: 100, title: "Sample Safe App", root: makeSampleSafeAppWindow())

        let result = try await broker.submit(
            .waitForUI(WaitForUIRequest(sessionID: session.sessionID, predicate: .elementAppears, roleQuery: nil, titleQuery: "Does Not Exist", timeoutMilliseconds: 300)),
            requestID: UUID(), deadline: farFutureDeadline
        )
        guard case .uiWaitResult(let waitResult) = result else { return XCTFail("Expected .uiWaitResult") }
        XCTAssertFalse(waitResult.satisfied)
        XCTAssertTrue(waitResult.timedOut)
    }

    /// `06-agent-documentation-security.md` section 8: "Stop button cancels
    /// current wait/capture." Proves Stop interrupts a `wait_for_ui` call
    /// well before its (much longer) timeout would naturally elapse — the
    /// per-tick poll check, not the timeout, is what ends the call. This is
    /// exactly the kind of threading/cancellation-race code the standing
    /// WP6/WP7 lesson (a single green run proves little) applies to; it is
    /// included in the required 10-consecutive-run stress pass.
    func testStopEndsInFlightWaitForUIPromptlyRatherThanRunningToTimeout() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        applicationLaunching.setRunning(bundleIdentifier: session.bundleIdentifier, pid: 100)
        axInspecting.setWindow(pid: 100, title: "Sample Safe App", root: makeSampleSafeAppWindow())

        let longTimeoutMilliseconds = 15_000 // the hard maximum
        let waitTask = Task {
            try await broker.submit(
                .waitForUI(WaitForUIRequest(sessionID: session.sessionID, predicate: .elementAppears, roleQuery: nil, titleQuery: "Never Appears", timeoutMilliseconds: longTimeoutMilliseconds)),
                requestID: UUID(), deadline: Date().addingTimeInterval(30)
            )
        }

        // Let the wait actually start polling, then Stop the session.
        try await Task.sleep(nanoseconds: 200_000_000)
        let stopStartedAt = Date()
        _ = try await broker.submit(.documentationSessionEnd(DocumentationSessionEndRequest(sessionID: session.sessionID)), requestID: UUID(), deadline: farFutureDeadline)

        do {
            _ = try await waitTask.value
            XCTFail("Expected the wait to end with cancelled once Stop was invoked")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .cancelled)
        }
        let elapsed = Date().timeIntervalSince(stopStartedAt)
        XCTAssertLessThan(elapsed, 2.0, "Stop must end an in-flight wait_for_ui within about one poll tick, not the full \(longTimeoutMilliseconds)ms timeout")
    }

    func testWaitForUIEnabledStateEqualsUsesLiveStateNotSnapshotTimeState() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker)
        let snapshot = try await inspectSampleSafeApp(broker, session: session)
        let saveRef = try XCTUnwrap(findRef(snapshot, title: "Save"))
        axInspecting.setEnabled(false, forID: "save-button")

        let waitTask = Task {
            try await broker.submit(
                .waitForUI(WaitForUIRequest(sessionID: session.sessionID, predicate: .enabledStateEquals, elementRef: saveRef, expectedBool: true, timeoutMilliseconds: 3000)),
                requestID: UUID(), deadline: Date().addingTimeInterval(10)
            )
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        axInspecting.setEnabled(true, forID: "save-button")

        let result = try await waitTask.value
        guard case .uiWaitResult(let waitResult) = result else { return XCTFail("Expected .uiWaitResult") }
        XCTAssertTrue(waitResult.satisfied)
    }

    // MARK: - Coverage states: sample-safe-app and custom-canvas fixtures
    // (`08-implementation-work-packages.md` WP8 verification)

    /// "A sample safe app can be navigated through at least three functions
    /// and produce a complete manifest plus Markdown using an external
    /// agent." The Markdown/external-agent half happens entirely outside
    /// BerryShot's process (`06-agent-documentation-security.md` section 1)
    /// and is out of scope for an automated unit test; this proves the
    /// BerryShot-owned half — a session can record three independently
    /// verified steps against the fixture and the resulting manifest
    /// reports all three as verified coverage.
    func testSampleSafeAppSupportsThreeVerifiedDocumentedFunctions() async throws {
        let broker = makeBroker(windows: [
            makeWindowFixture(id: 1, bundleIdentifier: "com.example.SafeApp"),
            makeWindowFixture(id: 2, bundleIdentifier: "com.example.SafeApp"),
            makeWindowFixture(id: 3, bundleIdentifier: "com.example.SafeApp")
        ])
        let session = try await beginSession(broker, bundleIdentifier: "com.example.SafeApp")

        let features = ["Enable Notifications", "Search", "Save Document"]
        for (index, feature) in features.enumerated() {
            let windowID = UInt32(index + 1)
            _ = try await broker.submit(
                .documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest(sessionID: session.sessionID, windowID: windowID, feature: feature, navigationSummary: ["Main", feature], verification: .verified, notes: [])),
                requestID: UUID(), deadline: farFutureDeadline
            )
        }

        let statusResult = try await broker.submit(.documentationSessionStatus(DocumentationSessionStatusRequest(sessionID: session.sessionID)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .documentationSession(let status) = statusResult else { return XCTFail("Expected .documentationSession") }
        XCTAssertEqual(status.steps.count, 3)
        XCTAssertEqual(status.coverage.verified.count, 3)
        XCTAssertTrue(status.coverage.blocked.isEmpty)
        XCTAssertTrue(status.coverage.conditional.isEmpty)
    }

    /// "A custom-canvas/incomplete AX app is reported conditional/blocked
    /// rather than complete." The fixture's AX tree has no actionable
    /// elements at all (`makeCustomCanvasAppWindow`); `inspect_ui` honestly
    /// reflects that (empty action lists throughout), and a caller that
    /// still wants to document it must explicitly record the step as
    /// `.conditional`/`.blocked` — nothing here can silently promote an
    /// unverifiable capture to `.verified`.
    func testCustomCanvasAppInspectUIReportsNoActionableElements() async throws {
        let broker = makeBroker()
        let session = try await beginSession(broker, bundleIdentifier: "com.example.CanvasApp")
        applicationLaunching.setRunning(bundleIdentifier: session.bundleIdentifier, pid: 300)
        axInspecting.setWindow(pid: 300, title: "Custom Canvas App", root: makeCustomCanvasAppWindow())

        let result = try await broker.submit(.inspectUI(InspectUIRequest(sessionID: session.sessionID, maxDepth: 6, maxNodes: 100)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .uiSnapshot(let snapshot) = result else { return XCTFail("Expected .uiSnapshot") }

        func collectActions(_ node: AXNodeDTO) -> [UIActionKind] {
            node.actions + node.children.flatMap(collectActions)
        }
        XCTAssertTrue(collectActions(snapshot.root).isEmpty, "the canvas fixture must never appear to support any allowlisted action")
    }

    func testCustomCanvasAppCaptureStepMustBeRecordedAsBlockedNotVerified() async throws {
        let broker = makeBroker(windows: [makeWindowFixture(id: 1, bundleIdentifier: "com.example.CanvasApp")])
        let session = try await beginSession(broker, bundleIdentifier: "com.example.CanvasApp")

        let result = try await broker.submit(
            .documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest(sessionID: session.sessionID, windowID: 1, feature: "Canvas drawing tool", navigationSummary: [], verification: .blocked, notes: ["AX tree exposes no actionable elements"])),
            requestID: UUID(), deadline: farFutureDeadline
        )
        guard case .documentationSession(let updated) = result else { return XCTFail("Expected .documentationSession") }
        XCTAssertEqual(updated.coverage.blocked.count, 1)
        XCTAssertTrue(updated.coverage.verified.isEmpty, "an incomplete-AX app must never be counted as verified coverage")
    }
}
