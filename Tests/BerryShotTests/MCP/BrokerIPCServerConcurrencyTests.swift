import XCTest
import BerryShotIPC
import os
#if canImport(Darwin)
import Darwin
#endif
@testable import BerryShot

/// `NSLock`-guarded string collector for use from `DispatchQueue.concurrentPerform`
/// closures in this file. `@unchecked Sendable` is safe here because every
/// access to `items` — the only stored state — goes through `add`, which
/// holds `lock` for the entire mutation.
private final class ThreadSafeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func add(_ item: String) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

/// Stress test backing `BrokerIPCServer`'s `@unchecked Sendable` doc-comment
/// justification (`08-implementation-work-packages.md` WP6 anti-pattern
/// guard: "Do not silence strict concurrency with broad `@unchecked
/// Sendable`" — the justification promised here is that every mutable
/// property is guarded by `stateLock`). Many connections hammer the server
/// concurrently from multiple threads; if the lock discipline were wrong,
/// this either crashes, hangs, or produces a response/request mismatch.
final class BrokerIPCServerConcurrencyTests: XCTestCase {
    func testManyConcurrentConnectionsAreEachServicedCorrectly() throws {
        let baseDirectory = makeTestBrokerBaseDirectory()
        defer { removeTestBrokerBaseDirectory(baseDirectory) }

        let server = BrokerIPCServer(broker: makeTestBroker(), baseDirectory: baseDirectory)
        defer { server.stop() }
        let descriptor = try server.start()

        let connectionCount = 25
        let requestsPerConnection = 4
        let expectation = expectation(description: "all connections finish")
        expectation.expectedFulfillmentCount = connectionCount
        let failures = ThreadSafeCollector()

        DispatchQueue.concurrentPerform(iterations: connectionCount) { index in
            defer { expectation.fulfill() }

            guard let fd = TestIPCClient.connect(path: descriptor.socketPath) else {
                failures.add("connection \(index) failed to connect")
                return
            }
            defer { close(fd) }

            for requestIndex in 0..<requestsPerConnection {
                let requestID = UUID()
                let request = BrokerRequest(
                    requestID: requestID,
                    deadline: Date().addingTimeInterval(30),
                    sessionToken: descriptor.sessionToken,
                    operation: .permissionsStatus
                )
                guard let payload = try? JSONEncoder().encode(request) else {
                    failures.add("connection \(index) request \(requestIndex) failed to encode")
                    return
                }
                TestIPCClient.send(payload, on: fd)

                guard let responseData = TestIPCClient.readOneFrame(from: fd),
                      let response = try? JSONDecoder().decode(BrokerResponse.self, from: responseData) else {
                    failures.add("connection \(index) request \(requestIndex) got no valid response")
                    return
                }
                guard response.requestID == requestID else {
                    failures.add("connection \(index) request \(requestIndex) got mismatched requestID \(response.requestID) != \(requestID)")
                    return
                }
                guard case .permissionsStatus = response.result else {
                    failures.add("connection \(index) request \(requestIndex) got unexpected result \(String(describing: response.result)) error \(String(describing: response.error))")
                    return
                }
            }
        }

        wait(for: [expectation], timeout: 30)
        let collected = failures.snapshot
        XCTAssertTrue(collected.isEmpty, "concurrency failures: \(collected.joined(separator: "; "))")
    }

    func testConcurrentConnectionsIncludingSomeRejectedPeersDoNotCorruptState() throws {
        let baseDirectory = makeTestBrokerBaseDirectory()
        defer { removeTestBrokerBaseDirectory(baseDirectory) }

        // Every other connection is "authorized"; the rest present a
        // mismatched UID and must be rejected without affecting the
        // authorized ones running concurrently on other threads.
        final class AlternatingLookup: PeerCredentialLookup, @unchecked Sendable {
            private let counter = OSAllocatedUnfairLock(initialState: 0)
            let ownerUID: UInt32
            init(ownerUID: UInt32) { self.ownerUID = ownerUID }
            func peerUID(forFileDescriptor fileDescriptor: Int32) -> UInt32? {
                let value = counter.withLock { state -> Int in
                    state += 1
                    return state
                }
                return value.isMultiple(of: 2) ? ownerUID : ownerUID &+ 1
            }
        }

        let ownerUID = UInt32(getuid())
        let server = BrokerIPCServer(broker: makeTestBroker(), baseDirectory: baseDirectory, peerCredentialLookup: AlternatingLookup(ownerUID: ownerUID), ownerUID: ownerUID)
        defer { server.stop() }
        let descriptor = try server.start()

        let connectionCount = 20
        let expectation = expectation(description: "all connections finish")
        expectation.expectedFulfillmentCount = connectionCount

        DispatchQueue.concurrentPerform(iterations: connectionCount) { index in
            defer { expectation.fulfill() }
            guard let fd = TestIPCClient.connect(path: descriptor.socketPath) else { return }
            defer { close(fd) }

            let request = BrokerRequest(deadline: Date().addingTimeInterval(30), sessionToken: descriptor.sessionToken, operation: .ping)
            guard let payload = try? JSONEncoder().encode(request) else { return }
            TestIPCClient.send(payload, on: fd)
            // Either a valid pong (authorized) or EOF/timeout (rejected) is
            // acceptable here; what this test actually asserts is that the
            // process never crashes/hangs and the server is still healthy
            // afterward, proving concurrent accept/reject/dispatch doesn't
            // corrupt `BrokerIPCServer`'s shared state.
            _ = TestIPCClient.readOneFrame(from: fd)
        }

        wait(for: [expectation], timeout: 30)
        XCTAssertTrue(server.isRunningNow, "the server must still be healthy after a mix of authorized/rejected concurrent peers")
    }
}
