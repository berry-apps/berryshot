import Foundation
import Logging
import MCP
import BerryShotIPC

/// Builds the `BerryShotMCP` stdio server and registers WP6's read-only
/// tool set: `permissions_status`, `list_applications`, `list_windows`.
/// `capture_window`/`capture_application`/`get_capture_manifest` and any
/// MCP resource (`berryshot://captures/...`) are explicitly out of scope
/// here — WP7 adds the artifact store and capture tools
/// (`08-implementation-work-packages.md` WP6 goal: "without yet exposing
/// full production tools").
///
/// Every handler here only validates arguments, calls `IPCClient`, and
/// shapes the result — no ScreenCaptureKit/Accessibility import, no
/// filesystem path acceptance, matching the WP6 anti-pattern guards.
public enum MCPServerFactory {
    /// Default per-call deadline for WP6's tools. None of section 3's
    /// tool input schemas define a client-supplied `deadline_ms` for these
    /// three read-only tools (that field only appears on the capture tools
    /// WP7 adds), so this is an internal bound, not a tool argument.
    static let defaultOperationDeadline: TimeInterval = 10

    /// `async` so every handler is registered before this returns — the
    /// caller must be able to call `server.start(transport:)` immediately
    /// afterward without a race where a client's very first `tools/list`
    /// could arrive before `withMethodHandler` has run.
    public static func makeServer(ipcClient: IPCClient, log: Logger) async -> Server {
        let server = Server(
            name: "BerryShot",
            version: HelperVersion.current,
            capabilities: .init(
                resources: .init(subscribe: false, listChanged: false),
                tools: .init(listChanged: false)
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: Self.tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            await Self.callTool(params: params, ipcClient: ipcClient, log: log)
        }

        await server.withMethodHandler(ListResources.self) { _ in
            // No artifact store exists yet (WP7); every capture/manifest/OCR
            // resource URI is added there.
            .init(resources: [])
        }

        await server.withMethodHandler(ReadResource.self) { params in
            throw MCPError.invalidParams("Unknown resource URI: \(params.uri)")
        }

        return server
    }

    // MARK: - Tool schemas

    private static let permissionsStatusTool = Tool(
        name: "permissions_status",
        description: "Report whether BerryShot currently has Screen Recording/Accessibility permission and whether the GUI is reachable. Does not open System Settings or request permission.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false)
        ])
    )

    private static let listApplicationsTool = Tool(
        name: "list_applications",
        description: "List eligible on-screen applications by bundle identifier.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string"), "maxLength": .int(200)]),
                "limit": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(100)]),
                "cursor": .object(["type": .string("string")])
            ]),
            "additionalProperties": .bool(false)
        ])
    )

    private static let listWindowsTool = Tool(
        name: "list_windows",
        description: "List eligible on-screen windows for one application, identified by bundle identifier.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "bundle_id": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(255)]),
                "limit": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(100)]),
                "cursor": .object(["type": .string("string")])
            ]),
            "required": .array([.string("bundle_id")]),
            "additionalProperties": .bool(false)
        ])
    )

    private static var tools: [Tool] {
        [permissionsStatusTool, listApplicationsTool, listWindowsTool]
    }

    // MARK: - Tool dispatch

    private static func callTool(params: CallTool.Parameters, ipcClient: IPCClient, log: Logger) async -> CallTool.Result {
        do {
            switch params.name {
            case "permissions_status":
                guard (params.arguments ?? [:]).isEmpty else {
                    return errorResult(code: .invalidArgument, message: "permissions_status takes no arguments")
                }
                let result = try await ipcClient.send(.permissionsStatus, deadline: Date().addingTimeInterval(defaultOperationDeadline))
                guard case .permissionsStatus(let status) = result else {
                    return errorResult(code: .internalError, message: "Unexpected broker result shape")
                }
                return try successResult(status)

            case "list_applications":
                let request = try parseListApplicationsArguments(params.arguments)
                let result = try await ipcClient.send(.listApplications(request), deadline: Date().addingTimeInterval(defaultOperationDeadline))
                guard case .applications(let page) = result else {
                    return errorResult(code: .internalError, message: "Unexpected broker result shape")
                }
                return try successResult(page)

            case "list_windows":
                let request = try parseListWindowsArguments(params.arguments)
                let result = try await ipcClient.send(.listWindows(request), deadline: Date().addingTimeInterval(defaultOperationDeadline))
                guard case .windows(let page) = result else {
                    return errorResult(code: .internalError, message: "Unexpected broker result shape")
                }
                return try successResult(page)

            default:
                return errorResult(code: .invalidArgument, message: "Unknown tool: \(params.name)")
            }
        } catch let error as ToolArgumentError {
            return errorResult(code: .invalidArgument, message: error.message)
        } catch let error as IPCClientError {
            log.error("IPC request failed", metadata: ["tool": "\(params.name)", "error": "\(error)"])
            return errorResult(code: mapIPCError(error).code, message: mapIPCError(error).message)
        } catch {
            log.error("Unexpected error handling tool call", metadata: ["tool": "\(params.name)", "error": "\(error)"])
            return errorResult(code: .internalError, message: "Internal error")
        }
    }

    // MARK: - Argument parsing

    private struct ToolArgumentError: Error {
        let message: String
    }

    private static func parseListApplicationsArguments(_ arguments: [String: Value]?) throws -> ListApplicationsRequest {
        let arguments = arguments ?? [:]
        try rejectUnknownKeys(arguments, allowed: ["query", "limit", "cursor"])

        let query = try optionalString(arguments["query"], field: "query", maxLength: 200)
        let limit = try optionalBoundedInt(arguments["limit"], field: "limit", defaultValue: 50, minimum: 1, maximum: 100)
        let cursor = try optionalString(arguments["cursor"], field: "cursor", maxLength: nil)
        return ListApplicationsRequest(query: query, limit: limit, cursor: cursor)
    }

    private static func parseListWindowsArguments(_ arguments: [String: Value]?) throws -> ListWindowsRequest {
        let arguments = arguments ?? [:]
        try rejectUnknownKeys(arguments, allowed: ["bundle_id", "limit", "cursor"])

        guard let bundleIDValue = arguments["bundle_id"], case .string(let bundleID) = bundleIDValue, !bundleID.isEmpty, bundleID.count <= 255 else {
            throw ToolArgumentError(message: "bundle_id is required and must be a non-empty string of at most 255 characters")
        }
        let limit = try optionalBoundedInt(arguments["limit"], field: "limit", defaultValue: 50, minimum: 1, maximum: 100)
        let cursor = try optionalString(arguments["cursor"], field: "cursor", maxLength: nil)
        return ListWindowsRequest(bundleIdentifier: bundleID, limit: limit, cursor: cursor)
    }

    private static func rejectUnknownKeys(_ arguments: [String: Value], allowed: Set<String>) throws {
        for key in arguments.keys where !allowed.contains(key) {
            throw ToolArgumentError(message: "Unknown argument: \(key)")
        }
    }

    private static func optionalString(_ value: Value?, field: String, maxLength: Int?) throws -> String? {
        guard let value else { return nil }
        guard case .string(let string) = value else {
            throw ToolArgumentError(message: "\(field) must be a string")
        }
        if let maxLength, string.count > maxLength {
            throw ToolArgumentError(message: "\(field) must be at most \(maxLength) characters")
        }
        return string
    }

    private static func optionalBoundedInt(_ value: Value?, field: String, defaultValue: Int, minimum: Int, maximum: Int) throws -> Int {
        guard let value else { return defaultValue }
        guard case .int(let intValue) = value else {
            throw ToolArgumentError(message: "\(field) must be an integer")
        }
        guard intValue >= minimum, intValue <= maximum else {
            throw ToolArgumentError(message: "\(field) must be between \(minimum) and \(maximum)")
        }
        return intValue
    }

    // MARK: - Result shaping

    private static func successResult<T: Codable>(_ payload: T) throws -> CallTool.Result {
        let jsonData = try JSONEncoder().encode(payload)
        let jsonText = String(data: jsonData, encoding: .utf8) ?? "{}"
        return try CallTool.Result(
            content: [.text(text: jsonText, annotations: nil, _meta: nil)],
            structuredContent: payload,
            isError: false
        )
    }

    private static func errorResult(code: BrokerErrorCode, message: String) -> CallTool.Result {
        let errorDTO = BrokerErrorDTO(code: code, message: message)
        let jsonText: String
        if let data = try? JSONEncoder().encode(errorDTO), let text = String(data: data, encoding: .utf8) {
            jsonText = text
        } else {
            jsonText = "{\"code\":\"\(code.rawValue)\"}"
        }
        return CallTool.Result(content: [.text(text: jsonText, annotations: nil, _meta: nil)], isError: true)
    }

    /// Maps a transport-level `IPCClientError` to the stable MCP tool error
    /// codes from `05-mcp-server-contract.md` section 4. IPC-transport-only
    /// codes (`unauthorized`, `protocolVersionMismatch`, `malformedRequest`)
    /// never reach a tool caller verbatim — see `BrokerErrorCode`'s doc
    /// comment for why.
    private static func mapIPCError(_ error: IPCClientError) -> (code: BrokerErrorCode, message: String) {
        switch error {
        case .descriptorUnavailable, .descriptorInvalid:
            return (.berryshotUnavailable, "BerryShot is not running or MCP integration is not enabled")
        case .connectionFailed:
            return (.brokerUnavailable, "Could not reach the BerryShot broker")
        case .malformedResponse, .requestIDMismatch:
            return (.internalError, "Internal error")
        case .deadlineExceeded:
            return (.deadlineExceeded, "The request exceeded its deadline")
        case .brokerError(let dto):
            switch dto.code {
            case .unauthorized, .protocolVersionMismatch, .malformedRequest:
                return (.brokerUnavailable, "Could not reach the BerryShot broker")
            default:
                return (dto.code, dto.message)
            }
        }
    }
}

enum HelperVersion {
    static let current = "0.1.0"
}
