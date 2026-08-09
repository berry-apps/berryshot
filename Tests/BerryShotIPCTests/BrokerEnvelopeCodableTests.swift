import XCTest
@testable import BerryShotIPC

final class BrokerEnvelopeCodableTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testPingRequestRoundTrips() throws {
        let request = BrokerRequest(
            deadline: Date(timeIntervalSince1970: 1_700_000_000),
            sessionToken: "token123",
            operation: .ping
        )
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(BrokerRequest.self, from: data)
        XCTAssertEqual(decoded, request)
    }

    func testListApplicationsRequestRoundTrips() throws {
        let request = BrokerRequest(
            deadline: Date(timeIntervalSince1970: 1_700_000_000),
            sessionToken: "token123",
            operation: .listApplications(.init(query: "notes", limit: 10, cursor: "5"))
        )
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(BrokerRequest.self, from: data)
        XCTAssertEqual(decoded, request)
    }

    func testListWindowsRequestRoundTrips() throws {
        let request = BrokerRequest(
            deadline: Date(timeIntervalSince1970: 1_700_000_000),
            sessionToken: "token123",
            operation: .listWindows(.init(bundleIdentifier: "com.example.App", limit: 20, cursor: nil))
        )
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(BrokerRequest.self, from: data)
        XCTAssertEqual(decoded, request)
    }

    func testCancelRequestRoundTrips() throws {
        let id = UUID()
        let request = BrokerRequest(
            deadline: Date(timeIntervalSince1970: 1_700_000_000),
            sessionToken: "token123",
            operation: .cancel(id)
        )
        let data = try encoder.encode(request)
        let decoded = try decoder.decode(BrokerRequest.self, from: data)
        XCTAssertEqual(decoded, request)
        guard case .cancel(let decodedID) = decoded.operation else {
            return XCTFail("Expected .cancel")
        }
        XCTAssertEqual(decodedID, id)
    }

    func testSuccessResponseRoundTrips() throws {
        let response = BrokerResponse.success(
            requestID: UUID(),
            result: .applications(.init(applications: [
                ApplicationSummaryDTO(id: "com.example.App", applicationName: "Example", processID: 100, isFrontmost: true, windowCount: 2)
            ], nextCursor: nil))
        )
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(BrokerResponse.self, from: data)
        XCTAssertEqual(decoded, response)
    }

    func testFailureResponseRoundTrips() throws {
        let response = BrokerResponse.failure(
            requestID: UUID(),
            error: BrokerErrorDTO(code: .rateLimited, message: "Too many pending requests")
        )
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(BrokerResponse.self, from: data)
        XCTAssertEqual(decoded, response)
    }

    func testAllStableErrorCodesRoundTripThroughRawValue() throws {
        // Locks these to `05-mcp-server-contract.md` section 4's exact
        // strings; a typo here would silently break MCP client error
        // mapping in a later work package.
        let expected: [BrokerErrorCode: String] = [
            .permissionDenied: "permission_denied",
            .restartRequired: "restart_required",
            .berryshotUnavailable: "berryshot_unavailable",
            .brokerUnavailable: "broker_unavailable",
            .invalidArgument: "invalid_argument",
            .applicationNotFound: "application_not_found",
            .windowNotAvailable: "window_not_available",
            .windowIdentityChanged: "window_identity_changed",
            .redactionUnavailable: "redaction_unavailable",
            .redactionReviewRequired: "redaction_review_required",
            .deadlineExceeded: "deadline_exceeded",
            .cancelled: "cancelled",
            .resourceNotFound: "resource_not_found",
            .resourceExpired: "resource_expired",
            .rateLimited: "rate_limited",
            .internalError: "internal_error"
        ]
        for (code, rawValue) in expected {
            XCTAssertEqual(code.rawValue, rawValue)
        }
    }

    func testUnknownRequestIDSentinelIsAllZeroUUID() {
        XCTAssertEqual(BrokerResponse.unknownRequestID.uuidString, "00000000-0000-0000-0000-000000000000")
    }
}
