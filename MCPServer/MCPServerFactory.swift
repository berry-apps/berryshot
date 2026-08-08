import Foundation
import Logging
import MCP
import BerryShotIPC

/// Builds the `BerryShotMCP` stdio server and registers the full read-only
/// MVP tool set from `05-mcp-server-contract.md` section 3:
/// `permissions_status`, `list_applications`, `list_windows` (WP6), plus
/// WP7's `capture_window`, `capture_application`, and `get_capture_manifest`,
/// together with the `berryshot://captures/{id}/image|manifest|ocr`
/// resource reads.
///
/// Every handler here only validates arguments, calls `IPCClient`, and
/// shapes the result — no ScreenCaptureKit/Accessibility import, no
/// filesystem path accepted from a client (only a broker-issued path is
/// ever opened, and only after `ArtifactResourceAccess` re-verifies
/// containment), matching the WP6/WP7 anti-pattern guards.
public enum MCPServerFactory {
    /// Default per-call deadline for tools that do not expose their own
    /// `deadline_ms` argument (`permissions_status`, `list_applications`,
    /// `list_windows`, `get_capture_manifest`, and the internal
    /// resolve-artifact-resource round trips capture tools make). The
    /// capture tools use their own client-supplied, validated `deadline_ms`
    /// instead.
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
            try await Self.callTool(params: params, ipcClient: ipcClient, server: server, log: log)
        }

        await server.withMethodHandler(ListResources.self) { _ in
            // Tool-returned resource links are not assumed to appear
            // automatically in `resources/list`
            // (`05-mcp-server-contract.md` section 6); clients read
            // capture resources directly by the opaque URI a capture tool
            // already returned.
            .init(resources: [])
        }

        await server.withMethodHandler(ReadResource.self) { params in
            try await Self.readResource(uri: params.uri, ipcClient: ipcClient, log: log)
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

    /// Shared by `capture_window` and `capture_application`'s schemas so
    /// the two tools cannot silently drift apart.
    private static let redactionPolicySchema: Value = .object([
        "type": .string("string"),
        "enum": .array([.string("none"), .string("suggest"), .string("required")])
    ])
    private static let redactionStyleSchema: Value = .object([
        "type": .string("string"),
        "enum": .array([.string("blur"), .string("pixelate"), .string("solid")])
    ])
    private static let previewMaxEdgeSchema: Value = .object([
        "type": .string("integer"), "minimum": .int(320), "maximum": .int(1280)
    ])
    private static let deadlineMillisecondsSchema: Value = .object([
        "type": .string("integer"), "minimum": .int(IPCProtocol.minDeadlineMilliseconds), "maximum": .int(IPCProtocol.maxDeadlineMilliseconds)
    ])

    private static let captureWindowTool = Tool(
        name: "capture_window",
        description: "Capture one application window, apply the requested redaction policy, and return a bounded preview plus resource links to the full image and manifest. Read-only: never captures the desktop or unrelated applications.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "window_id": .object(["type": .string("integer"), "minimum": .int(0), "maximum": .int(4_294_967_295)]),
                "expected_bundle_id": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(255)]),
                "redaction_policy": redactionPolicySchema,
                "redaction_style": redactionStyleSchema,
                "ocr": .object(["type": .string("boolean")]),
                "preview_max_edge": previewMaxEdgeSchema,
                "deadline_ms": deadlineMillisecondsSchema
            ]),
            "required": .array([.string("window_id"), .string("expected_bundle_id")]),
            "additionalProperties": .bool(false)
        ])
    )

    private static let captureApplicationTool = Tool(
        name: "capture_application",
        description: "Capture the frontmost window, or every eligible on-screen window, of one application. Returns one artifact and typed error per requested window; never composites multiple windows into one image.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "bundle_id": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(255)]),
                "window_policy": .object([
                    "type": .string("string"),
                    "enum": .array([.string("frontmostWindow"), .string("allOnScreenWindows")])
                ]),
                "redaction_policy": redactionPolicySchema,
                "redaction_style": redactionStyleSchema,
                "ocr": .object(["type": .string("boolean")]),
                "preview_max_edge": previewMaxEdgeSchema,
                "deadline_ms": deadlineMillisecondsSchema,
                "max_windows": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(20)])
            ]),
            "required": .array([.string("bundle_id"), .string("window_policy")]),
            "additionalProperties": .bool(false)
        ])
    )

    private static let getCaptureManifestTool = Tool(
        name: "get_capture_manifest",
        description: "Fetch the immutable, sanitized manifest for a previously captured artifact by its opaque capture id.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "capture_id": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(200)])
            ]),
            "required": .array([.string("capture_id")]),
            "additionalProperties": .bool(false)
        ])
    )

    private static var tools: [Tool] {
        [
            permissionsStatusTool,
            listApplicationsTool,
            listWindowsTool,
            captureWindowTool,
            captureApplicationTool,
            getCaptureManifestTool
        ]
    }

    // MARK: - Tool dispatch

    private static func callTool(params: CallTool.Parameters, ipcClient: IPCClient, server: Server, log: Logger) async throws -> CallTool.Result {
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

            case "capture_window":
                let parsed = try parseCaptureWindowArguments(params.arguments)
                let deadline = Date().addingTimeInterval(TimeInterval(parsed.deadlineMilliseconds) / 1000)
                let result = try await ipcClient.send(.captureWindow(parsed.ipcRequest), deadline: deadline)
                guard case .manifest(let manifest) = result else {
                    return errorResult(code: .internalError, message: "Unexpected broker result shape")
                }
                return await buildCaptureWindowResult(manifest: manifest, previewMaxEdge: parsed.ipcRequest.previewMaxEdge, ipcClient: ipcClient, log: log)

            case "capture_application":
                let parsed = try parseCaptureApplicationArguments(params.arguments)
                return try await handleCaptureApplication(parsed, server: server, meta: params._meta, ipcClient: ipcClient, log: log)

            case "get_capture_manifest":
                let captureID = try parseGetCaptureManifestArguments(params.arguments)
                let result = try await ipcClient.send(.getCaptureManifest(GetCaptureManifestRequest(captureID: captureID)), deadline: Date().addingTimeInterval(defaultOperationDeadline))
                guard case .manifest(let manifest) = result else {
                    return errorResult(code: .internalError, message: "Unexpected broker result shape")
                }
                return try successResult(manifest)

            default:
                return errorResult(code: .invalidArgument, message: "Unknown tool: \(params.name)")
            }
        } catch is CancellationError {
            // Advisory cancellation (`notifications/cancelled`): propagate
            // so the SDK's request wrapper suppresses the response entirely
            // per the MCP spec, instead of racing to compute/send a result
            // for a call the client already gave up on.
            throw CancellationError()
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

    /// Builds the three-part capture result contract
    /// (`05-mcp-server-contract.md` section 5): bounded inline preview,
    /// resource links, and text/structured metadata. The preview is built
    /// by downsizing the exact bytes just written to the artifact store —
    /// never a second, independent render — so its pixels are guaranteed
    /// to match the full resource by construction.
    private static func buildCaptureWindowResult(manifest: CaptureManifestDTO, previewMaxEdge: Int, ipcClient: IPCClient, log: Logger) async -> CallTool.Result {
        do {
            let resolved = try await ipcClient.send(
                .resolveArtifactResource(ResolveArtifactResourceRequest(captureID: manifest.captureID, kind: .image)),
                deadline: Date().addingTimeInterval(defaultOperationDeadline)
            )
            guard case .artifactResource(let location) = resolved else {
                return errorResult(code: .internalError, message: "Unexpected broker result shape")
            }
            let fullImageData = try ArtifactResourceAccess.readData(location, expectedRoot: ArtifactResourceAccess.expectedArtifactsRoot(baseDirectory: ipcClient.baseDirectory))
            let previewData = try CapturePreviewRenderer.boundedPreviewPNG(from: fullImageData, maxEdge: previewMaxEdge)

            var content: [Tool.Content] = [
                .text(text: manifestJSONText(manifest), annotations: nil, _meta: nil),
                .image(data: previewData.base64EncodedString(), mimeType: "image/png", annotations: nil, _meta: nil),
                .resourceLink(uri: manifest.resourceURI, name: "capture-image-\(manifest.captureID)", title: "Captured window image", description: nil, mimeType: "image/png"),
                .resourceLink(uri: manifest.manifestURI, name: "capture-manifest-\(manifest.captureID)", title: "Capture manifest", description: nil, mimeType: "application/json")
            ]
            if let ocrURI = manifest.ocrURI {
                content.append(.resourceLink(uri: ocrURI, name: "capture-ocr-\(manifest.captureID)", title: "Capture OCR text", description: nil, mimeType: "text/plain"))
            }

            return try CallTool.Result(content: content, structuredContent: manifest, isError: false)
        } catch let error as IPCClientError {
            let mapped = mapIPCError(error)
            return errorResult(code: mapped.code, message: mapped.message)
        } catch {
            log.error("Failed to build capture preview", metadata: ["capture_id": "\(manifest.captureID)", "error": "\(error)"])
            return errorResult(code: .internalError, message: "The capture succeeded, but its preview could not be prepared")
        }
    }

    /// `capture_application` deliberately does *not* inline a preview image
    /// per window: up to `max_windows` (default 10, hard max 20) inline
    /// images would multiply "full images exhaust model context"
    /// (`10-decisions-risks-open-questions.md` section 3) far past what one
    /// `capture_window` call spends. Every window still gets its own
    /// `capture_id`/resource links/manifest in structured content, so a
    /// caller that wants a specific window's preview can fetch it with
    /// `capture_window` or a direct resource read.
    private static func handleCaptureApplication(
        _ parsed: ParsedCaptureApplicationArguments,
        server: Server,
        meta: Metadata?,
        ipcClient: IPCClient,
        log: Logger
    ) async throws -> CallTool.Result {
        let listResult: BrokerResult
        do {
            listResult = try await ipcClient.send(
                .listWindows(ListWindowsRequest(bundleIdentifier: parsed.bundleID, limit: 100, cursor: nil)),
                deadline: Date().addingTimeInterval(defaultOperationDeadline)
            )
        } catch let error as IPCClientError {
            let mapped = mapIPCError(error)
            return errorResult(code: mapped.code, message: mapped.message)
        }
        guard case .windows(let page) = listResult else {
            return errorResult(code: .internalError, message: "Unexpected broker result shape")
        }

        let targetWindows: [WindowSummaryDTO]
        switch parsed.windowPolicy {
        case .frontmostWindow:
            // Best-effort only: `list_windows`' underlying discovery does
            // not expose a verified per-window z-order signal within one
            // application (see the PR's "Known gaps" section), so this is
            // the first window `list_windows` itself would return for this
            // bundle, not a hardware-verified frontmost window.
            guard let first = page.windows.first else {
                return errorResult(code: .windowNotAvailable, message: "No eligible on-screen windows for this application")
            }
            targetWindows = [first]
        case .allOnScreenWindows:
            targetWindows = Array(page.windows.prefix(parsed.maxWindows))
        }

        var outcomes: [CaptureApplicationWindowOutcomeJSON] = []
        let total = targetWindows.count
        for (index, window) in targetWindows.enumerated() {
            try Task.checkCancellation()

            let request = CaptureWindowRequest(
                windowID: window.id,
                expectedBundleIdentifier: parsed.bundleID,
                redactionPolicy: parsed.redactionPolicy,
                redactionStyle: parsed.redactionStyle,
                ocr: parsed.ocr,
                previewMaxEdge: parsed.previewMaxEdge
            )
            let deadline = Date().addingTimeInterval(TimeInterval(parsed.deadlineMilliseconds) / 1000)
            do {
                let result = try await ipcClient.send(.captureWindow(request), deadline: deadline)
                guard case .manifest(let manifest) = result else {
                    outcomes.append(.failure(windowID: window.id, code: .internalError, message: "Unexpected broker result shape"))
                    continue
                }
                outcomes.append(.success(manifest))
            } catch let error as IPCClientError {
                let mapped = mapIPCError(error)
                outcomes.append(.failure(windowID: window.id, code: mapped.code, message: mapped.message))
            }

            if let token = meta?.progressToken {
                try? await server.notify(ProgressNotification.message(.init(
                    progressToken: token,
                    progress: Double(index + 1),
                    total: Double(total),
                    message: "Captured window \(index + 1) of \(total)"
                )))
            }
        }

        let succeeded = outcomes.filter(\.isSuccess).count
        let structured = CaptureApplicationResultJSON(
            bundleIdentifier: parsed.bundleID,
            windowPolicy: parsed.windowPolicy.rawValue,
            requested: total,
            succeeded: succeeded,
            windows: outcomes
        )
        let summaryText = "Captured \(succeeded)/\(total) window(s) for \(parsed.bundleID)."
        return try CallTool.Result(
            content: [.text(text: summaryText, annotations: nil, _meta: nil)],
            structuredContent: structured,
            isError: succeeded == 0 && total > 0
        )
    }

    // MARK: - Resource reads

    private static func readResource(uri: String, ipcClient: IPCClient, log: Logger) async throws -> ReadResource.Result {
        guard let parsed = ArtifactResourceURI.parse(uri) else {
            throw MCPError.invalidParams("Unknown resource URI: \(uri)")
        }

        let result: BrokerResult
        do {
            result = try await ipcClient.send(
                .resolveArtifactResource(ResolveArtifactResourceRequest(captureID: parsed.captureID, kind: parsed.kind)),
                deadline: Date().addingTimeInterval(defaultOperationDeadline)
            )
        } catch let error as IPCClientError {
            let mapped = mapIPCError(error)
            throw MCPError.invalidParams("\(mapped.code.rawValue): \(mapped.message)")
        }
        guard case .artifactResource(let location) = result else {
            throw MCPError.internalError("Unexpected broker result shape")
        }

        let data: Data
        do {
            data = try ArtifactResourceAccess.readData(location, expectedRoot: ArtifactResourceAccess.expectedArtifactsRoot(baseDirectory: ipcClient.baseDirectory))
        } catch {
            log.error("Artifact resource read failed", metadata: ["uri": "\(uri)", "error": "\(error)"])
            throw MCPError.internalError("Could not read the requested resource")
        }

        switch parsed.kind {
        case .image:
            return .init(contents: [.binary(data, uri: uri, mimeType: location.mimeType)])
        case .manifest, .ocr:
            let text = String(data: data, encoding: .utf8) ?? ""
            return .init(contents: [.text(text, uri: uri, mimeType: location.mimeType)])
        }
    }

    // MARK: - Argument parsing

    private struct ToolArgumentError: Error {
        let message: String
    }

    private struct ParsedCaptureWindowArguments {
        let ipcRequest: CaptureWindowRequest
        let deadlineMilliseconds: Int
    }

    private struct ParsedCaptureApplicationArguments {
        let bundleID: String
        let windowPolicy: IPCApplicationWindowPolicy
        let redactionPolicy: IPCRedactionPolicy
        let redactionStyle: IPCRedactionStyle
        let ocr: Bool
        let previewMaxEdge: Int
        let deadlineMilliseconds: Int
        let maxWindows: Int
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

    private static func parseCaptureWindowArguments(_ arguments: [String: Value]?) throws -> ParsedCaptureWindowArguments {
        let arguments = arguments ?? [:]
        try rejectUnknownKeys(arguments, allowed: ["window_id", "expected_bundle_id", "redaction_policy", "redaction_style", "ocr", "preview_max_edge", "deadline_ms"])

        guard let windowIDValue = arguments["window_id"] else {
            throw ToolArgumentError(message: "window_id is required")
        }
        let windowID = try requiredUInt32(windowIDValue, field: "window_id")

        guard let bundleIDValue = arguments["expected_bundle_id"], case .string(let bundleID) = bundleIDValue, !bundleID.isEmpty, bundleID.count <= 255 else {
            throw ToolArgumentError(message: "expected_bundle_id is required and must be a non-empty string of at most 255 characters")
        }

        let redactionPolicy: IPCRedactionPolicy = try optionalEnum(arguments["redaction_policy"], field: "redaction_policy", default: .required)
        let redactionStyle: IPCRedactionStyle = try optionalEnum(arguments["redaction_style"], field: "redaction_style", default: .solid)
        let ocr = try optionalBool(arguments["ocr"], field: "ocr", defaultValue: false)
        let previewMaxEdge = try optionalBoundedInt(arguments["preview_max_edge"], field: "preview_max_edge", defaultValue: 960, minimum: 320, maximum: 1280)
        let deadlineMilliseconds = try optionalBoundedInt(
            arguments["deadline_ms"], field: "deadline_ms", defaultValue: 30_000,
            minimum: IPCProtocol.minDeadlineMilliseconds, maximum: IPCProtocol.maxDeadlineMilliseconds
        )

        return ParsedCaptureWindowArguments(
            ipcRequest: CaptureWindowRequest(
                windowID: windowID,
                expectedBundleIdentifier: bundleID,
                redactionPolicy: redactionPolicy,
                redactionStyle: redactionStyle,
                ocr: ocr,
                previewMaxEdge: previewMaxEdge
            ),
            deadlineMilliseconds: deadlineMilliseconds
        )
    }

    private static func parseCaptureApplicationArguments(_ arguments: [String: Value]?) throws -> ParsedCaptureApplicationArguments {
        let arguments = arguments ?? [:]
        try rejectUnknownKeys(arguments, allowed: ["bundle_id", "window_policy", "redaction_policy", "redaction_style", "ocr", "preview_max_edge", "deadline_ms", "max_windows"])

        guard let bundleIDValue = arguments["bundle_id"], case .string(let bundleID) = bundleIDValue, !bundleID.isEmpty, bundleID.count <= 255 else {
            throw ToolArgumentError(message: "bundle_id is required and must be a non-empty string of at most 255 characters")
        }
        guard let windowPolicyValue = arguments["window_policy"], case .string(let windowPolicyRaw) = windowPolicyValue,
              let windowPolicy = IPCApplicationWindowPolicy(rawValue: windowPolicyRaw) else {
            throw ToolArgumentError(message: "window_policy is required and must be one of: frontmostWindow, allOnScreenWindows")
        }

        let redactionPolicy: IPCRedactionPolicy = try optionalEnum(arguments["redaction_policy"], field: "redaction_policy", default: .required)
        let redactionStyle: IPCRedactionStyle = try optionalEnum(arguments["redaction_style"], field: "redaction_style", default: .solid)
        let ocr = try optionalBool(arguments["ocr"], field: "ocr", defaultValue: false)
        let previewMaxEdge = try optionalBoundedInt(arguments["preview_max_edge"], field: "preview_max_edge", defaultValue: 960, minimum: 320, maximum: 1280)
        let deadlineMilliseconds = try optionalBoundedInt(
            arguments["deadline_ms"], field: "deadline_ms", defaultValue: 30_000,
            minimum: IPCProtocol.minDeadlineMilliseconds, maximum: IPCProtocol.maxDeadlineMilliseconds
        )
        let maxWindows = try optionalBoundedInt(arguments["max_windows"], field: "max_windows", defaultValue: 10, minimum: 1, maximum: 20)

        return ParsedCaptureApplicationArguments(
            bundleID: bundleID,
            windowPolicy: windowPolicy,
            redactionPolicy: redactionPolicy,
            redactionStyle: redactionStyle,
            ocr: ocr,
            previewMaxEdge: previewMaxEdge,
            deadlineMilliseconds: deadlineMilliseconds,
            maxWindows: maxWindows
        )
    }

    private static func parseGetCaptureManifestArguments(_ arguments: [String: Value]?) throws -> String {
        let arguments = arguments ?? [:]
        try rejectUnknownKeys(arguments, allowed: ["capture_id"])
        guard let value = arguments["capture_id"], case .string(let captureID) = value, !captureID.isEmpty, captureID.count <= 200 else {
            throw ToolArgumentError(message: "capture_id is required and must be a non-empty string of at most 200 characters")
        }
        return captureID
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

    private static func optionalBool(_ value: Value?, field: String, defaultValue: Bool) throws -> Bool {
        guard let value else { return defaultValue }
        guard case .bool(let boolValue) = value else {
            throw ToolArgumentError(message: "\(field) must be a boolean")
        }
        return boolValue
    }

    private static func requiredUInt32(_ value: Value, field: String) throws -> UInt32 {
        guard case .int(let intValue) = value, intValue >= 0, intValue <= Int(UInt32.max) else {
            throw ToolArgumentError(message: "\(field) must be an unsigned 32-bit integer")
        }
        return UInt32(intValue)
    }

    private static func optionalEnum<T: RawRepresentable>(_ value: Value?, field: String, default defaultValue: T) throws -> T where T.RawValue == String {
        guard let value else { return defaultValue }
        guard case .string(let raw) = value, let parsed = T(rawValue: raw) else {
            throw ToolArgumentError(message: "\(field) has an unrecognized value")
        }
        return parsed
    }

    // MARK: - Result shaping

    private static func successResult<T: Codable>(_ payload: T) throws -> CallTool.Result {
        return try CallTool.Result(
            content: [.text(text: manifestJSONText(payload), annotations: nil, _meta: nil)],
            structuredContent: payload,
            isError: false
        )
    }

    private static func manifestJSONText<T: Encodable>(_ payload: T) -> String {
        guard let jsonData = try? JSONEncoder().encode(payload), let text = String(data: jsonData, encoding: .utf8) else {
            return "{}"
        }
        return text
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

/// `capture_application`'s per-window structured result entry: either a
/// full manifest (success) or a stable error code/message (failure) —
/// never both — so a caller can tell which windows to retry.
private struct CaptureApplicationWindowOutcomeJSON: Codable {
    let windowID: UInt32
    let manifest: CaptureManifestDTO?
    let errorCode: String?
    let errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case windowID = "window_id"
        case manifest
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }

    var isSuccess: Bool { manifest != nil }

    static func success(_ manifest: CaptureManifestDTO) -> Self {
        .init(windowID: manifest.windowID, manifest: manifest, errorCode: nil, errorMessage: nil)
    }

    static func failure(windowID: UInt32, code: BrokerErrorCode, message: String) -> Self {
        .init(windowID: windowID, manifest: nil, errorCode: code.rawValue, errorMessage: message)
    }
}

private struct CaptureApplicationResultJSON: Codable {
    let bundleIdentifier: String
    let windowPolicy: String
    let requested: Int
    let succeeded: Int
    let windows: [CaptureApplicationWindowOutcomeJSON]

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "bundle_id"
        case windowPolicy = "window_policy"
        case requested
        case succeeded
        case windows
    }
}

enum HelperVersion {
    static let current = "0.1.0"
}
