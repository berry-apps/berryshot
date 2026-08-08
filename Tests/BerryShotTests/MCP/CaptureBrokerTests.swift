import XCTest
@testable import BerryShot
import BerryShotIPC

private struct FakeDiscovery: CaptureBrokerDiscovering {
    var applications: [ApplicationDescriptor] = []
    var windows: [WindowDescriptor] = []
    var applicationsError: Error?
    var windowsError: Error?
    /// Optional hook so a test can block `discoverWindows()` mid-flight to
    /// exercise cancellation of an in-flight (not just queued) operation.
    var onDiscoverWindows: (@Sendable () async -> Void)?

    func discoverApplications() async throws -> [ApplicationDescriptor] {
        if let applicationsError { throw applicationsError }
        return applications
    }

    func discoverWindows() async throws -> [WindowDescriptor] {
        if let onDiscoverWindows { await onDiscoverWindows() }
        if let windowsError { throw windowsError }
        return windows
    }
}

private struct FakePermissions: CaptureBrokerPermissionsChecking {
    var screenCapture: Bool
    var accessibility: Bool
    func screenCaptureGranted() -> Bool { screenCapture }
    func accessibilityGranted() -> Bool { accessibility }
}

private func makeWindow(
    id: UInt32,
    bundleIdentifier: String = "com.example.App",
    applicationName: String = "Example",
    title: String = "Untitled",
    isFrontmost: Bool = false
) -> WindowDescriptor {
    WindowDescriptor(
        id: id,
        bundleIdentifier: bundleIdentifier,
        applicationName: applicationName,
        processID: 100,
        title: title,
        frameInScreenPoints: CGRectDTO(x: 0, y: 0, width: 400, height: 300),
        isOnScreen: true,
        isFrontmost: isFrontmost
    )
}

private let farFutureDeadline = Date().addingTimeInterval(60)

final class CaptureBrokerTests: XCTestCase {
    // MARK: - ping / permissionsStatus

    func testPingReturnsPong() async throws {
        let broker = CaptureBroker(discovery: FakeDiscovery(), permissions: FakePermissions(screenCapture: true, accessibility: true))
        let result = try await broker.submit(.ping, requestID: UUID(), deadline: farFutureDeadline)
        XCTAssertEqual(result, .pong)
    }

    func testPermissionsStatusReflectsInjectedPermissions() async throws {
        let broker = CaptureBroker(discovery: FakeDiscovery(), permissions: FakePermissions(screenCapture: true, accessibility: false))
        let result = try await broker.submit(.permissionsStatus, requestID: UUID(), deadline: farFutureDeadline)
        guard case .permissionsStatus(let status) = result else {
            return XCTFail("Expected .permissionsStatus")
        }
        XCTAssertEqual(status.screenCapture, .granted)
        XCTAssertEqual(status.accessibility, .denied)
        XCTAssertTrue(status.berryshotRunning)
        XCTAssertEqual(status.brokerProtocolVersion, IPCProtocol.currentVersion)
    }

    // MARK: - listApplications

    func testListApplicationsReturnsDiscoveredApplications() async throws {
        let apps = [
            ApplicationDescriptor(id: "com.example.A", applicationName: "A", processID: 1, windowCount: 1, isFrontmost: false),
            ApplicationDescriptor(id: "com.example.B", applicationName: "B", processID: 2, windowCount: 2, isFrontmost: true)
        ]
        let broker = CaptureBroker(discovery: FakeDiscovery(applications: apps))
        let result = try await broker.submit(.listApplications(.init()), requestID: UUID(), deadline: farFutureDeadline)
        guard case .applications(let page) = result else { return XCTFail("Expected .applications") }
        XCTAssertEqual(page.applications.map(\.id), ["com.example.A", "com.example.B"])
        XCTAssertNil(page.nextCursor)
    }

    func testListApplicationsFiltersByQueryCaseInsensitively() async throws {
        let apps = [
            ApplicationDescriptor(id: "com.example.Notes", applicationName: "Notes", processID: 1, windowCount: 1, isFrontmost: false),
            ApplicationDescriptor(id: "com.example.Mail", applicationName: "Mail", processID: 2, windowCount: 1, isFrontmost: false)
        ]
        let broker = CaptureBroker(discovery: FakeDiscovery(applications: apps))
        let result = try await broker.submit(.listApplications(.init(query: "not")), requestID: UUID(), deadline: farFutureDeadline)
        guard case .applications(let page) = result else { return XCTFail("Expected .applications") }
        XCTAssertEqual(page.applications.map(\.id), ["com.example.Notes"])
    }

    func testListApplicationsPaginatesWithOpaqueCursor() async throws {
        let apps = (0..<5).map { ApplicationDescriptor(id: "com.example.App\($0)", applicationName: "App\($0)", processID: Int32($0), windowCount: 1, isFrontmost: false) }
        let broker = CaptureBroker(discovery: FakeDiscovery(applications: apps))

        let firstPage = try await broker.submit(.listApplications(.init(limit: 2)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .applications(let firstResult) = firstPage else { return XCTFail("Expected .applications") }
        XCTAssertEqual(firstResult.applications.count, 2)
        let cursor = try XCTUnwrap(firstResult.nextCursor)

        let secondPage = try await broker.submit(.listApplications(.init(limit: 2, cursor: cursor)), requestID: UUID(), deadline: farFutureDeadline)
        guard case .applications(let secondResult) = secondPage else { return XCTFail("Expected .applications") }
        XCTAssertEqual(secondResult.applications.count, 2)
        XCTAssertNotEqual(firstResult.applications.map(\.id), secondResult.applications.map(\.id))
    }

    func testListApplicationsRejectsLimitOutOfRange() async throws {
        let broker = CaptureBroker(discovery: FakeDiscovery())
        do {
            _ = try await broker.submit(.listApplications(.init(limit: 0)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }

    func testListApplicationsRejectsQueryOver200Characters() async throws {
        let broker = CaptureBroker(discovery: FakeDiscovery())
        let longQuery = String(repeating: "a", count: 201)
        do {
            _ = try await broker.submit(.listApplications(.init(query: longQuery)), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }

    func testListApplicationsSanitizesControlCharactersAndBoundsLength() async throws {
        let dirty = "Evil\u{0007}App" + String(repeating: "X", count: 600)
        let apps = [ApplicationDescriptor(id: "com.example.Evil", applicationName: dirty, processID: 1, windowCount: 1, isFrontmost: false)]
        let broker = CaptureBroker(discovery: FakeDiscovery(applications: apps))
        let result = try await broker.submit(.listApplications(.init()), requestID: UUID(), deadline: farFutureDeadline)
        guard case .applications(let page) = result else { return XCTFail("Expected .applications") }
        let name = try XCTUnwrap(page.applications.first?.applicationName)
        XCTAssertFalse(name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
        XCTAssertLessThanOrEqual(name.count, 500)
    }

    // MARK: - listWindows

    func testListWindowsReturnsOnlyWindowsForRequestedBundle() async throws {
        let windows = [
            makeWindow(id: 1, bundleIdentifier: "com.example.A", title: "Window A1"),
            makeWindow(id: 2, bundleIdentifier: "com.example.B", title: "Window B1")
        ]
        let broker = CaptureBroker(discovery: FakeDiscovery(windows: windows))
        let result = try await broker.submit(.listWindows(.init(bundleIdentifier: "com.example.A")), requestID: UUID(), deadline: farFutureDeadline)
        guard case .windows(let page) = result else { return XCTFail("Expected .windows") }
        XCTAssertEqual(page.windows.map(\.id), [1])
    }

    func testListWindowsRejectsEmptyBundleIdentifier() async throws {
        let broker = CaptureBroker(discovery: FakeDiscovery())
        do {
            _ = try await broker.submit(.listWindows(.init(bundleIdentifier: "")), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }

    func testListWindowsReturnsApplicationNotFoundWhenBundleHasNoEligibleWindows() async throws {
        let broker = CaptureBroker(discovery: FakeDiscovery(windows: [makeWindow(id: 1, bundleIdentifier: "com.example.Other")]))
        do {
            _ = try await broker.submit(.listWindows(.init(bundleIdentifier: "com.example.Missing")), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected application_not_found")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .applicationNotFound)
        }
    }

    func testListWindowsRejectsMalformedCursor() async throws {
        let broker = CaptureBroker(discovery: FakeDiscovery(windows: [makeWindow(id: 1)]))
        do {
            _ = try await broker.submit(.listWindows(.init(bundleIdentifier: "com.example.App", cursor: "not-a-number")), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected invalid_argument")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }

    func testDiscoveryFailureIsMappedToInternalErrorNotLeakedRaw() async throws {
        struct FixtureError: Error {}
        let broker = CaptureBroker(discovery: FakeDiscovery(applicationsError: FixtureError()))
        do {
            _ = try await broker.submit(.listApplications(.init()), requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected internal_error")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .internalError)
        }
    }

    // MARK: - Bounded queue

    func testQueueDepthBeyondLimitIsRejectedWithRateLimited() async throws {
        // A discovery fixture that blocks until we release it, so we can
        // fill the queue behind one in-flight request.
        let gate = Gate()
        let discovery = FakeDiscovery(windows: [], onDiscoverWindows: { await gate.wait() })
        let broker = CaptureBroker(discovery: discovery, maxQueueDepth: 2)

        // One in-flight (currently executing, blocked on the gate) + two
        // queued fills the bound exactly.
        let inFlight = Task { try await broker.submit(.listWindows(.init(bundleIdentifier: "com.example.App")), requestID: UUID(), deadline: farFutureDeadline) }
        // Give the drain loop a chance to dequeue the in-flight entry before
        // we saturate the queue with the next two.
        try await Task.sleep(nanoseconds: 20_000_000)

        async let queuedOne = broker.submit(.ping, requestID: UUID(), deadline: farFutureDeadline)
        async let queuedTwo = broker.submit(.ping, requestID: UUID(), deadline: farFutureDeadline)
        try await Task.sleep(nanoseconds: 20_000_000)

        do {
            _ = try await broker.submit(.ping, requestID: UUID(), deadline: farFutureDeadline)
            XCTFail("Expected rate_limited")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .rateLimited)
        }

        await gate.open()
        _ = try? await inFlight.value
        _ = try? await queuedOne
        _ = try? await queuedTwo
    }

    // MARK: - Deadlines

    func testAlreadyPassedDeadlineIsRejectedWithoutExecuting() async throws {
        actor CallCounter { var count = 0; func increment() { count += 1 } }
        let counter = CallCounter()
        let windowDiscovery = FakeDiscovery(windows: [makeWindow(id: 1)], onDiscoverWindows: { await counter.increment() })
        let broker = CaptureBroker(discovery: windowDiscovery)

        let pastDeadline = Date().addingTimeInterval(-1)
        do {
            _ = try await broker.submit(.listWindows(.init(bundleIdentifier: "com.example.App")), requestID: UUID(), deadline: pastDeadline)
            XCTFail("Expected deadline_exceeded")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .deadlineExceeded)
        }
        let calls = await counter.count
        XCTAssertEqual(calls, 0, "an already-expired deadline must not run the underlying discovery call")
    }

    // MARK: - Cancellation

    func testCancellingAQueuedRequestResumesItWithCancelled() async throws {
        let gate = Gate()
        let discovery = FakeDiscovery(windows: [makeWindow(id: 1)], onDiscoverWindows: { await gate.wait() })
        let broker = CaptureBroker(discovery: discovery)

        let inFlightID = UUID()
        let inFlight = Task { try await broker.submit(.listWindows(.init(bundleIdentifier: "com.example.App")), requestID: inFlightID, deadline: farFutureDeadline) }
        try await Task.sleep(nanoseconds: 20_000_000) // let it start executing and block on the gate

        let queuedID = UUID()
        let queued = Task { try await broker.submit(.ping, requestID: queuedID, deadline: farFutureDeadline) }
        try await Task.sleep(nanoseconds: 20_000_000) // let it actually enqueue

        await broker.cancel(requestID: queuedID)

        do {
            _ = try await queued.value
            XCTFail("Expected the queued request to be cancelled")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .cancelled)
        }

        await gate.open()
        _ = try? await inFlight.value
    }

    func testCancelAllDrainsQueueWithCancelledWithoutRunningThem() async throws {
        actor CallCounter { var count = 0; func increment() { count += 1 } }
        let counter = CallCounter()
        let gate = Gate()
        let discovery = FakeDiscovery(windows: [makeWindow(id: 1)], onDiscoverWindows: { await counter.increment(); await gate.wait() })
        let broker = CaptureBroker(discovery: discovery)

        let inFlight = Task { try? await broker.submit(.listWindows(.init(bundleIdentifier: "com.example.App")), requestID: UUID(), deadline: farFutureDeadline) }
        try await Task.sleep(nanoseconds: 20_000_000)

        let queued = Task { try await broker.submit(.ping, requestID: UUID(), deadline: farFutureDeadline) }
        try await Task.sleep(nanoseconds: 20_000_000)

        await broker.cancelAll()

        do {
            _ = try await queued.value
            XCTFail("Expected cancellation")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .cancelled)
        }

        await gate.open()
        _ = await inFlight.value
        let calls = await counter.count
        XCTAssertEqual(calls, 1, "cancelAll must not have executed the still-queued ping")
    }

    func testCancelOperationAcknowledgesAndCancelsTarget() async throws {
        let gate = Gate()
        let discovery = FakeDiscovery(windows: [makeWindow(id: 1)], onDiscoverWindows: { await gate.wait() })
        let broker = CaptureBroker(discovery: discovery)

        let targetID = UUID()
        let target = Task { try await broker.submit(.listWindows(.init(bundleIdentifier: "com.example.App")), requestID: targetID, deadline: farFutureDeadline) }
        try await Task.sleep(nanoseconds: 20_000_000)

        let queuedTargetID = UUID()
        let queuedTarget = Task { try await broker.submit(.ping, requestID: queuedTargetID, deadline: farFutureDeadline) }
        try await Task.sleep(nanoseconds: 20_000_000)

        let ack = try await broker.submit(.cancel(queuedTargetID), requestID: UUID(), deadline: farFutureDeadline)
        XCTAssertEqual(ack, .cancelAcknowledged)

        do {
            _ = try await queuedTarget.value
            XCTFail("Expected cancellation")
        } catch let error as BrokerOperationError {
            XCTAssertEqual(error.code, .cancelled)
        }

        await gate.open()
        _ = try? await target.value
    }
}

/// A tiny async gate used to force an operation to stay "in flight" until a
/// test explicitly releases it, so queue/cancellation behavior can be
/// exercised deterministically instead of racing on `Task.sleep`.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}
