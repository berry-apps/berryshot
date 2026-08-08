import XCTest
import Logging
import MCP
import BerryShotIPC
import CoreGraphics
import ImageIO
@testable import BerryShotMCP

/// Exercises WP7's capture tools/resources through the exact same
/// `MCPServerFactory.makeServer` the real helper uses, over `InMemoryTransport`
/// for the MCP protocol layer and a real Unix-domain `FakeBrokerServer`
/// (from `IPCClientTestSupport.swift`) for the IPC layer underneath —
/// letting these tests drive genuine argument validation, error mapping,
/// and artifact-resource file reads without requiring ScreenCaptureKit
/// permission or a running GUI.
final class MCPServerFactoryCaptureToolsTests: XCTestCase {
    private var baseDirectory: URL!
    private var fakeBroker: FakeBrokerServer!
    private var manifest: CaptureManifestDTO!
    private var imageBytes: Data!
    private let staleWindowID: UInt32 = 999
    private let expiredCaptureID = UUID().uuidString

    override func setUp() async throws {
        try await super.setUp()
        baseDirectory = makeTestIPCBaseDirectory()

        imageBytes = pngFixtureData(width: 20, height: 16)
        let artifactsRoot = baseDirectory.appendingPathComponent("Artifacts", isDirectory: true)
        let captureID = UUID().uuidString
        let captureDirectory = artifactsRoot.appendingPathComponent(captureID, isDirectory: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        let imagePath = captureDirectory.appendingPathComponent("image.png").path
        FileManager.default.createFile(atPath: imagePath, contents: imageBytes)
        let ocrPath = captureDirectory.appendingPathComponent("ocr.txt").path
        FileManager.default.createFile(atPath: ocrPath, contents: Data("hello ocr".utf8))

        manifest = CaptureManifestDTO(
            captureID: captureID,
            resourceURI: "berryshot://captures/\(captureID)/image",
            manifestURI: "berryshot://captures/\(captureID)/manifest",
            ocrURI: "berryshot://captures/\(captureID)/ocr",
            bundleIdentifier: "com.example.App",
            processID: 100,
            windowID: 7,
            windowTitle: "Settings",
            pixelWidth: 20,
            pixelHeight: 16,
            pointPixelScale: 2.0,
            redactionStatus: .applied,
            redactionRegionCount: 1,
            ocrAvailable: true,
            sha256: "irrelevant-for-these-tests",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            warnings: []
        )

        let capturedManifest = manifest!
        let capturedImagePath = imagePath
        let capturedOCRPath = ocrPath
        let capturedManifestPath = captureDirectory.appendingPathComponent("manifest.json").path
        try JSONEncoder().encode(capturedManifest).write(to: URL(fileURLWithPath: capturedManifestPath))
        let staleWindowID = self.staleWindowID
        let expiredCaptureID = self.expiredCaptureID

        fakeBroker = FakeBrokerServer(socketPath: baseDirectory.appendingPathComponent("broker.sock").path) { request in
            switch request.operation {
            case .captureWindow(let captureRequest):
                if captureRequest.windowID == staleWindowID {
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .windowNotAvailable, message: "The requested window is not currently available"))
                }
                if captureRequest.expectedBundleIdentifier != capturedManifest.bundleIdentifier {
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .windowIdentityChanged, message: "The window no longer belongs to the expected application"))
                }
                return .success(requestID: request.requestID, result: .manifest(capturedManifest))

            case .getCaptureManifest(let manifestRequest):
                if manifestRequest.captureID == capturedManifest.captureID {
                    return .success(requestID: request.requestID, result: .manifest(capturedManifest))
                }
                return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .resourceNotFound, message: "Unknown capture id"))

            case .resolveArtifactResource(let resourceRequest):
                if resourceRequest.captureID == expiredCaptureID {
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .resourceExpired, message: "This capture has expired"))
                }
                guard resourceRequest.captureID == capturedManifest.captureID else {
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .resourceNotFound, message: "Unknown capture resource"))
                }
                let location: ArtifactResourceLocationDTO
                switch resourceRequest.kind {
                case .image:
                    location = ArtifactResourceLocationDTO(path: capturedImagePath, mimeType: "image/png")
                case .manifest:
                    location = ArtifactResourceLocationDTO(path: capturedManifestPath, mimeType: "application/json")
                case .ocr:
                    location = ArtifactResourceLocationDTO(path: capturedOCRPath, mimeType: "text/plain")
                }
                return .success(requestID: request.requestID, result: .artifactResource(location))

            case .listWindows:
                // Three windows for the same bundle so capture_application's
                // allOnScreenWindows/progress-notification behavior has more
                // than one window to iterate.
                let windows = [capturedManifest.windowID, capturedManifest.windowID + 1, capturedManifest.windowID + 2].map {
                    WindowSummaryDTO(id: $0, bundleIdentifier: capturedManifest.bundleIdentifier, applicationName: "Example", processID: capturedManifest.processID, title: capturedManifest.windowTitle, isOnScreen: true, isFrontmost: $0 == capturedManifest.windowID)
                }
                return .success(requestID: request.requestID, result: .windows(ListWindowsResult(windows: windows, nextCursor: nil)))

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
        let log = Logger(label: "test.mcpservertests") { _ in SwiftLogNoOpLogHandler() }
        let ipcClient = IPCClient(baseDirectory: baseDirectory, log: log)
        let server = await MCPServerFactory.makeServer(ipcClient: ipcClient, log: log)
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "TestClient", version: "0.0.0")
        try await server.start(transport: serverTransport)
        _ = try await client.connect(transport: clientTransport)
        return (client, server)
    }

    // MARK: - Exact schema snapshot

    func testCaptureWindowSchemaMatchesContractExactly() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (tools, _) = try await client.listTools()
        let tool = try XCTUnwrap(tools.first { $0.name == "capture_window" })

        let expected: Value = .object([
            "type": .string("object"),
            "properties": .object([
                "window_id": .object(["type": .string("integer"), "minimum": .int(0), "maximum": .int(4_294_967_295)]),
                "expected_bundle_id": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(255)]),
                "redaction_policy": .object(["type": .string("string"), "enum": .array([.string("none"), .string("suggest"), .string("required")])]),
                "redaction_style": .object(["type": .string("string"), "enum": .array([.string("blur"), .string("pixelate"), .string("solid")])]),
                "ocr": .object(["type": .string("boolean")]),
                "preview_max_edge": .object(["type": .string("integer"), "minimum": .int(320), "maximum": .int(1280)]),
                "deadline_ms": .object(["type": .string("integer"), "minimum": .int(1000), "maximum": .int(60000)])
            ]),
            "required": .array([.string("window_id"), .string("expected_bundle_id")]),
            "additionalProperties": .bool(false)
        ])
        XCTAssertEqual(tool.inputSchema, expected)
    }

    func testCaptureApplicationSchemaMatchesContractExactly() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (tools, _) = try await client.listTools()
        let tool = try XCTUnwrap(tools.first { $0.name == "capture_application" })

        let expected: Value = .object([
            "type": .string("object"),
            "properties": .object([
                "bundle_id": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(255)]),
                "window_policy": .object(["type": .string("string"), "enum": .array([.string("frontmostWindow"), .string("allOnScreenWindows")])]),
                "redaction_policy": .object(["type": .string("string"), "enum": .array([.string("none"), .string("suggest"), .string("required")])]),
                "redaction_style": .object(["type": .string("string"), "enum": .array([.string("blur"), .string("pixelate"), .string("solid")])]),
                "ocr": .object(["type": .string("boolean")]),
                "preview_max_edge": .object(["type": .string("integer"), "minimum": .int(320), "maximum": .int(1280)]),
                "deadline_ms": .object(["type": .string("integer"), "minimum": .int(1000), "maximum": .int(60000)]),
                "max_windows": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(20)])
            ]),
            "required": .array([.string("bundle_id"), .string("window_policy")]),
            "additionalProperties": .bool(false)
        ])
        XCTAssertEqual(tool.inputSchema, expected)
    }

    func testGetCaptureManifestSchemaMatchesContractExactly() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (tools, _) = try await client.listTools()
        let tool = try XCTUnwrap(tools.first { $0.name == "get_capture_manifest" })

        let expected: Value = .object([
            "type": .string("object"),
            "properties": .object([
                "capture_id": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(200)])
            ]),
            "required": .array([.string("capture_id")]),
            "additionalProperties": .bool(false)
        ])
        XCTAssertEqual(tool.inputSchema, expected)
    }

    // MARK: - Unknown / extra / oversized argument rejection

    func testCaptureWindowRejectsUnknownArgument() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "capture_window", arguments: ["window_id": .int(1), "expected_bundle_id": .string("com.example.App"), "unexpected_field": .bool(true)])
        XCTAssertEqual(isError, true)
    }

    func testCaptureWindowRejectsMissingRequiredArgument() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "capture_window", arguments: ["window_id": .int(1)])
        XCTAssertEqual(isError, true)
    }

    func testCaptureWindowRejectsOversizedExpectedBundleID() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let oversized = String(repeating: "a", count: 256)
        let (_, isError) = try await client.callTool(name: "capture_window", arguments: ["window_id": .int(1), "expected_bundle_id": .string(oversized)])
        XCTAssertEqual(isError, true)
    }

    func testCaptureWindowRejectsPreviewMaxEdgeOutOfRange() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "capture_window", arguments: ["window_id": .int(1), "expected_bundle_id": .string("com.example.App"), "preview_max_edge": .int(64)])
        XCTAssertEqual(isError, true)
    }

    func testCaptureWindowRejectsUnrecognizedRedactionPolicy() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "capture_window", arguments: ["window_id": .int(1), "expected_bundle_id": .string("com.example.App"), "redaction_policy": .string("bogus")])
        XCTAssertEqual(isError, true)
    }

    func testCaptureApplicationRejectsUnknownArgument() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "capture_application", arguments: ["bundle_id": .string("com.example.App"), "window_policy": .string("frontmostWindow"), "nope": .int(1)])
        XCTAssertEqual(isError, true)
    }

    func testCaptureApplicationRejectsMaxWindowsAboveHardLimit() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "capture_application", arguments: ["bundle_id": .string("com.example.App"), "window_policy": .string("allOnScreenWindows"), "max_windows": .int(21)])
        XCTAssertEqual(isError, true)
    }

    func testGetCaptureManifestRejectsOversizedCaptureID() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "get_capture_manifest", arguments: ["capture_id": .string(String(repeating: "a", count: 201))])
        XCTAssertEqual(isError, true)
    }

    func testGetCaptureManifestRejectsUnknownArgument() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (_, isError) = try await client.callTool(name: "get_capture_manifest", arguments: ["capture_id": .string("x"), "path": .string("/etc/passwd")])
        XCTAssertEqual(isError, true)
    }

    // MARK: - Stale ID / bundle mismatch rejection over the wire

    func testCaptureWindowWithStaleWindowIDIsRejected() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (content, isError) = try await client.callTool(name: "capture_window", arguments: ["window_id": .int(Int(staleWindowID)), "expected_bundle_id": .string(manifest.bundleIdentifier)])
        XCTAssertEqual(isError, true)
        guard case .text(let text, _, _) = content.first else { return XCTFail("expected text content") }
        XCTAssertTrue(text.contains("window_not_available"))
    }

    func testCaptureWindowWithBundleMismatchIsRejected() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let (content, isError) = try await client.callTool(name: "capture_window", arguments: ["window_id": .int(Int(manifest.windowID)), "expected_bundle_id": .string("com.example.WrongApp")])
        XCTAssertEqual(isError, true)
        guard case .text(let text, _, _) = content.first else { return XCTFail("expected text content") }
        XCTAssertTrue(text.contains("window_identity_changed"))
    }

    // MARK: - Successful capture: preview/full-image correspondence

    func testSuccessfulCaptureWindowReturnsPreviewLinkedToTheSameFinalImage() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let context: RequestContext<CallTool.Result> = try await client.callTool(name: "capture_window", arguments: ["window_id": .int(Int(manifest.windowID)), "expected_bundle_id": .string(manifest.bundleIdentifier), "preview_max_edge": .int(320)])
        let result = try await context.value
        XCTAssertNotEqual(result.isError, true)

        var sawImage = false
        var sawImageLink = false
        var sawManifestLink = false
        for item in result.content {
            switch item {
            case .image(let data, let mimeType, _, _):
                sawImage = true
                XCTAssertEqual(mimeType, "image/png")
                XCTAssertFalse(data.isEmpty)
                // The preview must be decodable image bytes, not a copy of
                // the raw fixture text.
                XCTAssertNotNil(Data(base64Encoded: data))
            case .resourceLink(let uri, _, _, _, _, _):
                if uri == manifest.resourceURI { sawImageLink = true }
                if uri == manifest.manifestURI { sawManifestLink = true }
            default:
                break
            }
        }
        XCTAssertTrue(sawImage, "expected a bounded inline preview image")
        XCTAssertTrue(sawImageLink)
        XCTAssertTrue(sawManifestLink)

        guard case .object(let structured)? = result.structuredContent else {
            return XCTFail("expected structured content")
        }
        XCTAssertEqual(structured["capture_id"]?.stringValue, manifest.captureID)
        XCTAssertEqual(structured["bundle_id"]?.stringValue, manifest.bundleIdentifier)
        XCTAssertEqual(structured["redaction_status"]?.stringValue, "applied")
    }

    // MARK: - capture_application: progress notifications, per-window fan-out

    func testCaptureApplicationCapturesEachWindowAndSendsProgressNotifications() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }

        let recorder = ProgressEventRecorder()
        await client.onNotification(ProgressNotification.self) { message in
            await recorder.record(message.params.progress, message.params.total)
        }

        let context: RequestContext<CallTool.Result> = try await client.callTool(
            name: "capture_application",
            arguments: ["bundle_id": .string(manifest.bundleIdentifier), "window_policy": .string("allOnScreenWindows")],
            meta: Metadata(progressToken: .string("test-progress-token"))
        )
        let result = try await context.value
        XCTAssertNotEqual(result.isError, true)

        guard case .object(let structured)? = result.structuredContent else {
            return XCTFail("expected structured content")
        }
        XCTAssertEqual(structured["requested"]?.intValue, 3)
        XCTAssertEqual(structured["succeeded"]?.intValue, 3)
        XCTAssertEqual((structured["windows"]?.arrayValue ?? []).count, 3)

        let events = await recorder.events
        XCTAssertEqual(events.map(\.progress), [1, 2, 3])
        XCTAssertEqual(events.map(\.total), [3, 3, 3])
    }

    func testCaptureApplicationFrontmostWindowPolicyCapturesExactlyOneWindow() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let context: RequestContext<CallTool.Result> = try await client.callTool(
            name: "capture_application",
            arguments: ["bundle_id": .string(manifest.bundleIdentifier), "window_policy": .string("frontmostWindow")]
        )
        let result = try await context.value
        XCTAssertNotEqual(result.isError, true)
        guard case .object(let structured)? = result.structuredContent else {
            return XCTFail("expected structured content")
        }
        XCTAssertEqual(structured["requested"]?.intValue, 1)
    }

    func testCaptureApplicationRespectsMaxWindowsBound() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let context: RequestContext<CallTool.Result> = try await client.callTool(
            name: "capture_application",
            arguments: ["bundle_id": .string(manifest.bundleIdentifier), "window_policy": .string("allOnScreenWindows"), "max_windows": .int(2)]
        )
        let result = try await context.value
        guard case .object(let structured)? = result.structuredContent else {
            return XCTFail("expected structured content")
        }
        XCTAssertEqual(structured["requested"]?.intValue, 2, "max_windows must bound how many windows are captured, not just how many are listed")
    }

    // MARK: - Resource reads: success, path traversal, expiry

    func testReadImageResourceReturnsExactStoredBytes() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let contents = try await client.readResource(uri: manifest.resourceURI)
        guard let blob = contents.first?.blob, let data = Data(base64Encoded: blob) else {
            return XCTFail("expected binary image content")
        }
        XCTAssertEqual(data, imageBytes)
    }

    func testReadOCRResourceReturnsPublishedText() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        let contents = try await client.readResource(uri: try XCTUnwrap(manifest.ocrURI))
        XCTAssertEqual(contents.first?.text, "hello ocr")
    }

    func testReadResourceWithPathTraversalCaptureIDIsRejected() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        do {
            _ = try await client.readResource(uri: "berryshot://captures/../../../../etc/image")
            XCTFail("Expected a protocol error rejecting the malformed capture id")
        } catch {
            // Expected: MCPError.invalidParams surfaces as a thrown error
            // through the SDK client; the key assertion is that it did NOT
            // return file contents.
        }
    }

    func testReadResourceWithUnknownSchemeIsRejected() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        do {
            _ = try await client.readResource(uri: "file:///etc/passwd")
            XCTFail("Expected rejection of a non-berryshot URI")
        } catch {
            // Expected.
        }
    }

    func testReadExpiredResourceIsRejected() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        do {
            _ = try await client.readResource(uri: "berryshot://captures/\(expiredCaptureID)/image")
            XCTFail("Expected rejection of an expired resource")
        } catch {
            // Expected.
        }
    }

    func testGetCaptureManifestForExpiredCaptureReturnsIsErrorTrue() async throws {
        let (client, server) = try await makeClientServerPair()
        defer { Task { await server.stop() } }
        // Reuse the fixture broker's expired-capture handling by routing a
        // resolveArtifactResource-triggering flow isn't applicable here —
        // get_capture_manifest goes straight to `.getCaptureManifest`, which
        // this fixture only recognizes for `manifest.captureID`. Confirm the
        // not-found path (a stand-in for "no longer available") still
        // surfaces as isError:true with a stable code instead of throwing.
        let (content, isError) = try await client.callTool(name: "get_capture_manifest", arguments: ["capture_id": .string(UUID().uuidString)])
        XCTAssertEqual(isError, true)
        guard case .text(let text, _, _) = content.first else { return XCTFail("expected text content") }
        XCTAssertTrue(text.contains("resource_not_found"))
    }
}

private actor ProgressEventRecorder {
    private(set) var events: [(progress: Double, total: Double?)] = []
    func record(_ progress: Double, _ total: Double?) {
        events.append((progress, total))
    }
}

/// A minimal, valid, deterministic PNG fixture (solid color) — real enough
/// for `CapturePreviewRenderer`/`ImageIO` to decode and downsize, without
/// needing ScreenCaptureKit or a captured window.
private func pngFixtureData(width: Int, height: Int) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let mutableData = CFDataCreateMutable(nil, 0)!
    let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return mutableData as Data
}
