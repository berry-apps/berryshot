import Foundation

/// Request envelope crossing the private Unix-domain socket, matching the
/// shape recommended in `05-mcp-server-contract.md` section 7.
public struct BrokerRequest: Codable, Sendable, Equatable {
    public let protocolVersion: UInt16
    public let requestID: UUID
    public let deadline: Date
    public let sessionToken: String
    public let operation: BrokerOperation

    public init(
        protocolVersion: UInt16 = IPCProtocol.currentVersion,
        requestID: UUID = UUID(),
        deadline: Date,
        sessionToken: String,
        operation: BrokerOperation
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.deadline = deadline
        self.sessionToken = sessionToken
        self.operation = operation
    }
}

/// Response envelope. Exactly one of `result`/`error` is non-nil in a
/// well-formed response; `IPCClient` treats both-nil or both-non-nil as a
/// malformed response rather than guessing.
public struct BrokerResponse: Codable, Sendable, Equatable {
    public let protocolVersion: UInt16
    public let requestID: UUID
    public let result: BrokerResult?
    public let error: BrokerErrorDTO?

    public init(
        protocolVersion: UInt16 = IPCProtocol.currentVersion,
        requestID: UUID,
        result: BrokerResult?,
        error: BrokerErrorDTO?
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.result = result
        self.error = error
    }

    public static func success(requestID: UUID, result: BrokerResult) -> BrokerResponse {
        BrokerResponse(requestID: requestID, result: result, error: nil)
    }

    public static func failure(requestID: UUID, error: BrokerErrorDTO) -> BrokerResponse {
        BrokerResponse(requestID: requestID, result: nil, error: error)
    }

    /// A response the server sends when the platform-level `requestID` of
    /// the inbound request could not be determined at all (payload was not
    /// even parseable JSON). The helper must treat this sentinel ID as a
    /// fatal, non-retryable protocol error on that connection rather than
    /// trying to match it against a pending request.
    public static let unknownRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
