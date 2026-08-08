import XCTest
import MCP

/// WP6 task 1's required compile spike
/// (`05-mcp-server-contract.md` section 2): "The first commit of the MCP
/// issue must be a compile-only spike... Compile a minimal stdio server
/// with `ListTools`, `CallTool`, `ListResources`, and `ReadResource`
/// handlers. Compile one tool result containing text, inline image,
/// resource link, and structured metadata. Add a protocol smoke test using
/// the SDK client or recorded JSON-RPC requests."
///
/// This uses `InMemoryTransport` (not `StdioTransport`) because the goal
/// here is to lock exact constructors/signatures for the pinned
/// `modelcontextprotocol/swift-sdk` release `0.12.1`, not to exercise real
/// process framing — the stdout-cleanliness/subprocess-level behavior is
/// covered separately by `HelperStdoutProtocolTests`.
///
/// Exact working constructors/signatures recorded here (see also the PR
/// description's "Test evidence" section for the transcript this test
/// produces):
///
/// - `Server(name:version:capabilities:)` with
///   `Server.Capabilities(resources: .init(subscribe: false, listChanged: true), tools: .init(listChanged: false))`.
/// - `server.withMethodHandler(ListTools.self) { _ in .init(tools: [...]) }`.
/// - `Tool(name:description:inputSchema:)` where `inputSchema` is a `Value.object([...])`.
/// - `server.withMethodHandler(CallTool.self) { params in .init(content: [...], structuredContent:, isError:) }`.
/// - `Tool.Content.text(text:annotations:_meta:)`, `.image(data:mimeType:annotations:_meta:)`,
///   `.resourceLink(uri:name:title:description:mimeType:annotations:)`.
/// - `server.withMethodHandler(ListResources.self) { _ in .init(resources: [...]) }`.
/// - `server.withMethodHandler(ReadResource.self) { params in .init(contents: [.text(...)]) }`.
/// - `InMemoryTransport.createConnectedPair()` for an in-process client/server pair.
/// - `Client(name:version:).connect(transport:) async throws -> Initialize.Result`.
/// - `client.listTools()`, `client.callTool(name:arguments:)`, `client.listResources()`, `client.readResource(uri:)`.
final class MCPSDKCompileSpikeTests: XCTestCase {
    private static let toolName = "spike_echo"
    private static let resourceURI = "berryshot://spike/resource"

    private func makeServer() async -> Server {
        let server = Server(
            name: "BerryShotSpike",
            version: "0.0.0-spike",
            capabilities: .init(
                resources: .init(subscribe: false, listChanged: true),
                tools: .init(listChanged: false)
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            let tool = Tool(
                name: Self.toolName,
                description: "Compile-spike tool; not shipped to users.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "additionalProperties": .bool(false)
                ])
            )
            return .init(tools: [tool])
        }

        await server.withMethodHandler(CallTool.self) { params in
            guard params.name == Self.toolName else {
                return .init(content: [.text(text: "Unknown tool", annotations: nil, _meta: nil)], isError: true)
            }
            let tinyPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            struct SpikeMetadata: Codable {
                let echoed: Bool
            }
            return try .init(
                content: [
                    .text(text: "spike ok", annotations: nil, _meta: nil),
                    .image(data: tinyPNGBase64, mimeType: "image/png", annotations: nil, _meta: nil),
                    .resourceLink(
                        uri: Self.resourceURI,
                        name: "spike-resource",
                        title: "Spike Resource",
                        description: nil,
                        mimeType: "application/json"
                    )
                ],
                structuredContent: SpikeMetadata(echoed: true),
                isError: false
            )
        }

        await server.withMethodHandler(ListResources.self) { _ in
            .init(resources: [
                Resource(
                    name: "spike-resource",
                    uri: Self.resourceURI,
                    description: "Compile-spike resource",
                    mimeType: "application/json"
                )
            ])
        }

        await server.withMethodHandler(ReadResource.self) { params in
            guard params.uri == Self.resourceURI else {
                throw MCPError.invalidParams("Unknown resource URI: \(params.uri)")
            }
            return .init(contents: [.text("{\"spike\":true}", uri: params.uri, mimeType: "application/json")])
        }

        return server
    }

    func testMinimalServerCompilesAndHandlesInitializeListCallReadOverInMemoryTransport() async throws {
        let server = await makeServer()
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "BerryShotSpikeClient", version: "0.0.0-spike")

        try await server.start(transport: serverTransport)
        let initializeResult = try await client.connect(transport: clientTransport)

        XCTAssertEqual(initializeResult.serverInfo.name, "BerryShotSpike")
        XCTAssertFalse(initializeResult.protocolVersion.isEmpty)

        let (tools, _) = try await client.listTools()
        XCTAssertEqual(tools.map(\.name), [Self.toolName])

        let (content, isError) = try await client.callTool(name: Self.toolName, arguments: [:])
        XCTAssertEqual(isError, false)
        XCTAssertEqual(content.count, 3)

        guard case .text(let text, _, _) = content[0] else {
            return XCTFail("Expected first content item to be text")
        }
        XCTAssertEqual(text, "spike ok")

        guard case .image(_, let mimeType, _, _) = content[1] else {
            return XCTFail("Expected second content item to be an inline image")
        }
        XCTAssertEqual(mimeType, "image/png")

        guard case .resourceLink(let uri, let name, _, _, _, _) = content[2] else {
            return XCTFail("Expected third content item to be a resource link")
        }
        XCTAssertEqual(uri, Self.resourceURI)
        XCTAssertEqual(name, "spike-resource")

        let (resources, _) = try await client.listResources()
        XCTAssertEqual(resources.map(\.uri), [Self.resourceURI])

        let readContents = try await client.readResource(uri: Self.resourceURI)
        XCTAssertEqual(readContents.first?.text, "{\"spike\":true}")

        await server.stop()
    }
}
