import XCTest
import Logging
import MCP
import BerryShotIPC
@testable import BerryShotMCP

/// Exercises the WP8 documentation-session/guarded-AX-automation tools
/// through the exact same `MCPServerFactory.makeServer` the real helper
/// uses, mirroring `MCPServerFactoryCaptureToolsTests`'s
/// `InMemoryTransport` + `FakeBrokerServer` approach so these tests drive
/// genuine JSON Schema validation, argument parsing, and error mapping
/// without a running GUI or real Accessibility permission.
final class MCPServerFactoryDocumentationToolsTests: XCTestCase {
    private var baseDirectory: URL!
    private var fakeBroker: FakeBrokerServer!

    private let sessionID = "session-123"

    override func setUp() async throws {
        try await super.setUp()
        baseDirectory = makeTestIPCBaseDirectory()

        let sampleSession = DocumentationSessionDTO(
            sessionID: sessionID, bundleIdentifier: "com.example.App", displayName: "Test", mode: .interactive, status: .active,
            startedAt: "2026-01-01T00:00:00Z", expiresAt: "2026-01-01T01:00:00Z", allowLaunch: true,
            redactionPolicy: .required, redactionStyle: .solid, maxArtifacts: 20, artifactCount: 0,
            lastActionAt: "2026-01-01T00:00:00Z", lastActionDescription: "Session started", steps: [], coverage: .empty
        )
        let sampleNode = AXNodeDTO(
            ref: "ref-1", role: "AXButton", subrole: nil, title: "Save", descriptionText: nil,
            enabledState: true, focused: false, frame: AXFrameDTO(x: 0, y: 0, width: 80, height: 24), actions: [.press], childCount: 0, children: []
        )

        fakeBroker = FakeBrokerServer(socketPath: baseDirectory.appendingPathComponent("broker.sock").path) { request in
            switch request.operation {
            case .documentationSessionBegin, .documentationSessionStatus, .documentationSessionEnd:
                return .success(requestID: request.requestID, result: .documentationSession(sampleSession))
            case .documentationSessionCaptureStep(let stepRequest):
                if stepRequest.windowID == 999 {
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .bundleNotAllowed, message: "Wrong bundle"))
                }
                return .success(requestID: request.requestID, result: .documentationSession(sampleSession))
            case .launchApplication, .activateApplication:
                return .success(requestID: request.requestID, result: .applicationLaunch(ApplicationLaunchResultDTO(bundleIdentifier: "com.example.App", processID: 100, wasAlreadyRunning: false, isActive: true)))
            case .inspectUI:
                return .success(requestID: request.requestID, result: .uiSnapshot(UISnapshotDTO(sessionID: self.sessionID, bundleIdentifier: "com.example.App", processID: 100, generation: 1, windowTitle: "Window", root: sampleNode, truncatedByDepth: false, truncatedByNodeCount: false)))
            case .performUIAction(let actionRequest):
                if actionRequest.elementRef == "secure-ref" {
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .actionBlocked, message: "Secure field"))
                }
                return .success(requestID: request.requestID, result: .uiActionResult(UIActionResultDTO(sessionID: self.sessionID, elementRef: actionRequest.elementRef, action: actionRequest.action, performed: true, role: "AXButton")))
            case .waitForUI:
                return .success(requestID: request.requestID, result: .uiWaitResult(UIWaitResultDTO(sessionID: self.sessionID, satisfied: true, timedOut: false, elapsedMilliseconds: 10)))
            default:
                return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .internalError, message: "Unhandled fixture operation"))
            }
        }
        try fakeBroker.start()

        let descriptor = BrokerDescriptor(protocolVersion: IPCProtocol.currentVersion, socketPath: baseDirectory.appendingPathComponent("broker.sock").path, guiPID: ProcessInfo.processInfo.processIdentifier, expiresAt: Date().addingTimeInterval(3600), sessionToken: "test-token")
        try writeTestDescriptor(descriptor, to: baseDirectory)
    }

    override func tearDown() {
        fakeBroker?.stop()
        fakeBroker = nil
        removeTestIPCBaseDirectory(baseDirectory)
        baseDirectory = nil
        super.tearDown()
    }

    private func makeClientServerPair() async throws -> (client: Client, server: Server) {
        let log = Logger(label: "test.mcpdocstests") { _ in SwiftLogNoOpLogHandler() }
        let ipcClient = IPCClient(baseDirectory: baseDirectory, log: log)
        let server = await MCPServerFactory.makeServer(ipcClient: ipcClient, log: log)
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "TestClient", version: "0.0.0")
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)
        return (client, server)
    }

    // MARK: - Tool registration

    func testAllNineWP8ToolsAreRegistered() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (tools, _) = try await client.listTools()
        let names = Set(tools.map(\.name))
        let expected: Set<String> = [
            "documentation_session_begin", "documentation_session_status", "documentation_session_capture_step", "documentation_session_end",
            "launch_application", "activate_application", "inspect_ui", "perform_ui_action", "wait_for_ui"
        ]
        XCTAssertTrue(expected.isSubset(of: names), "missing tools: \(expected.subtracting(names))")
    }

    // MARK: - Schema snapshots (the tools most load-bearing for the security review)

    func testPerformUIActionSchemaOnlyAllowsTheFiveActionKinds() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (tools, _) = try await client.listTools()
        let tool = try XCTUnwrap(tools.first { $0.name == "perform_ui_action" })

        guard case .object(let schema) = tool.inputSchema,
              case .object(let properties) = schema["properties"],
              case .object(let actionSchema) = properties["action"],
              case .array(let enumValues) = actionSchema["enum"] else {
            return XCTFail("Unexpected schema shape")
        }
        let actions = enumValues.compactMap { value -> String? in if case .string(let s) = value { return s }; return nil }
        XCTAssertEqual(Set(actions), ["press", "showMenu", "increment", "decrement", "setValue"])
    }

    func testLaunchApplicationSchemaRequiresApprove() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (tools, _) = try await client.listTools()
        let tool = try XCTUnwrap(tools.first { $0.name == "launch_application" })
        guard case .object(let schema) = tool.inputSchema, case .array(let required) = schema["required"] else {
            return XCTFail("Unexpected schema shape")
        }
        let requiredNames = required.compactMap { value -> String? in if case .string(let s) = value { return s }; return nil }
        XCTAssertTrue(requiredNames.contains("approve"))
        XCTAssertTrue(requiredNames.contains("session_id"))
    }

    func testDocumentationSessionBeginSchemaHasNoBundleLevelRedactionPolicyChoice() async throws {
        // `06-agent-documentation-security.md`: MCP redaction is always
        // "required" for documentation sessions. The schema itself must not
        // offer a `redaction_policy` argument at all, so a client cannot
        // even attempt to request a weaker one.
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (tools, _) = try await client.listTools()
        let tool = try XCTUnwrap(tools.first { $0.name == "documentation_session_begin" })
        guard case .object(let schema) = tool.inputSchema, case .object(let properties) = schema["properties"] else {
            return XCTFail("Unexpected schema shape")
        }
        XCTAssertNil(properties["redaction_policy"])
    }

    // MARK: - Unknown/missing argument rejection

    func testDocumentationSessionBeginRejectsUnknownArgument() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "documentation_session_begin", arguments: [
            "bundle_id": .string("com.example.App"), "display_name": .string("Test"), "mode": .string("readOnly"), "unexpected": .bool(true)
        ])
        XCTAssertEqual(isError, true)
    }

    func testDocumentationSessionBeginRejectsMissingMode() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "documentation_session_begin", arguments: [
            "bundle_id": .string("com.example.App"), "display_name": .string("Test")
        ])
        XCTAssertEqual(isError, true)
    }

    func testPerformUIActionRejectsMissingSessionID() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "perform_ui_action", arguments: [
            "element_ref": .string("ref-1"), "action": .string("press")
        ])
        XCTAssertEqual(isError, true)
    }

    func testWaitForUIRejectsTimeoutAboveHardMaximum() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "wait_for_ui", arguments: [
            "session_id": .string(sessionID), "predicate": .string("window_title_contains"), "title_query": .string("Settings"), "timeout_ms": .int(20_000)
        ])
        XCTAssertEqual(isError, true)
    }

    func testInspectUIRejectsUnrecognizedElementCountBound() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "inspect_ui", arguments: [
            "session_id": .string(sessionID), "max_nodes": .int(10_000)
        ])
        XCTAssertEqual(isError, true)
    }

    // MARK: - Dispatch happy paths

    func testDocumentationSessionBeginDispatchesAndReturnsSession() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "documentation_session_begin", arguments: [
            "bundle_id": .string("com.example.App"), "display_name": .string("Test"), "mode": .string("interactive"), "allow_launch": .bool(true)
        ])
        XCTAssertEqual(isError, false)
    }

    func testDocumentationSessionCaptureStepDispatchesAndReturnsSession() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "documentation_session_capture_step", arguments: [
            "session_id": .string(sessionID), "window_id": .int(1), "feature": .string("General settings"), "verification": .string("verified")
        ])
        XCTAssertEqual(isError, false)
    }

    func testDocumentationSessionCaptureStepSurfacesBundleNotAllowedAsError() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "documentation_session_capture_step", arguments: [
            "session_id": .string(sessionID), "window_id": .int(999), "feature": .string("General settings"), "verification": .string("verified")
        ])
        XCTAssertEqual(isError, true)
    }

    func testInspectUIDispatchesAndReturnsSnapshot() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "inspect_ui", arguments: ["session_id": .string(sessionID)])
        XCTAssertEqual(isError, false)
    }

    func testPerformUIActionSurfacesActionBlockedAsError() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "perform_ui_action", arguments: [
            "session_id": .string(sessionID), "element_ref": .string("secure-ref"), "action": .string("setValue"), "value": .string("hunter2")
        ])
        XCTAssertEqual(isError, true)
    }

    func testWaitForUIDispatchesAndReturnsResult() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "wait_for_ui", arguments: [
            "session_id": .string(sessionID), "predicate": .string("window_title_contains"), "title_query": .string("Settings")
        ])
        XCTAssertEqual(isError, false)
    }

    func testLaunchApplicationDispatchesSuccessfully() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "launch_application", arguments: [
            "session_id": .string(sessionID), "approve": .bool(true)
        ])
        XCTAssertEqual(isError, false)
    }

    func testDocumentationSessionEndDispatchesSuccessfully() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "documentation_session_end", arguments: ["session_id": .string(sessionID)])
        XCTAssertEqual(isError, false)
    }
}
