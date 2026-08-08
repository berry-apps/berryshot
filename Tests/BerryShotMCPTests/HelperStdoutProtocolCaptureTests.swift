import XCTest
import CoreGraphics
import ImageIO
import BerryShotIPC
#if canImport(Darwin)
import Darwin
#endif

/// WP7's extension of `HelperStdoutProtocolTests`: spawns the real, built
/// `BerryShotMCP` binary exactly as an MCP client would, but this time with
/// a real fake broker listening on the Unix socket the helper's `IPCClient`
/// connects to, so the new capture tools' *success* path (not just their
/// error path) is exercised over the actual stdio transport — the closest
/// automated equivalent available in this environment to the plan's
/// "Codex and Claude Code can list, capture, see preview, and fetch full
/// resource" verification bullet (`05-mcp-server-contract.md` section 9),
/// since no interactive Codex/Claude Code session is available here.
///
/// This is also the test most likely to catch a WP6-style stdout-purity
/// regression in the *new* code paths specifically (preview downsizing,
/// artifact file reads, resource serving) — the same class of bug that
/// slipped through WP6's own review and was only caught by independent
/// post-merge stress testing (see issue #19 / PR #20).
final class HelperStdoutProtocolCaptureTests: XCTestCase {
    private var tempHome: URL!
    private var mcpDirectory: URL!
    private var fakeBroker: FakeBrokerServer!

    private let captureID = UUID().uuidString
    private let staleWindowID: UInt32 = 999
    private let windowID: UInt32 = 7
    private let bundleID = "com.example.App"
    private var imageBytes: Data!

    override func setUpWithError() throws {
        try super.setUpWithError()
        signal(SIGPIPE, SIG_IGN)

        // A short, fixed-prefix path directly under `/tmp` rather than
        // `FileManager.default.temporaryDirectory`: this test needs a real
        // listening Unix-domain socket at
        // `<HOME>/Library/Application Support/BerryShot/MCP/broker.sock`,
        // and `sockaddr_un.sun_path` has a ~104-byte limit that
        // `$TMPDIR`-based paths on this machine exceed once that suffix is
        // appended (see `makeTestBrokerBaseDirectory()` in
        // `BrokerIPCServerTestSupport.swift` for the same constraint).
        tempHome = URL(fileURLWithPath: "/tmp/bsh-\(UUID().uuidString.prefix(8))", isDirectory: true)
        mcpDirectory = tempHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("BerryShot", isDirectory: true)
            .appendingPathComponent("MCP", isDirectory: true)
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        imageBytes = Self.pngFixtureData(width: 16, height: 12)
        let artifactDirectory = mcpDirectory.appendingPathComponent("Artifacts", isDirectory: true).appendingPathComponent(captureID, isDirectory: true)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let imagePath = artifactDirectory.appendingPathComponent("image.png").path
        FileManager.default.createFile(atPath: imagePath, contents: imageBytes)

        let manifest = CaptureManifestDTO(
            captureID: captureID,
            resourceURI: "berryshot://captures/\(captureID)/image",
            manifestURI: "berryshot://captures/\(captureID)/manifest",
            ocrURI: nil,
            bundleIdentifier: bundleID,
            processID: 100,
            windowID: windowID,
            windowTitle: "Settings",
            pixelWidth: 16,
            pixelHeight: 12,
            pointPixelScale: 2.0,
            redactionStatus: .clean,
            redactionRegionCount: 0,
            ocrAvailable: false,
            sha256: "fixture",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            warnings: []
        )
        let manifestPath = artifactDirectory.appendingPathComponent("manifest.json").path
        try JSONEncoder().encode(manifest).write(to: URL(fileURLWithPath: manifestPath))

        let socketPath = mcpDirectory.appendingPathComponent("broker.sock").path
        let fixtureWindowID = windowID
        let fixtureStaleID = staleWindowID
        let fixtureBundleID = bundleID
        let fixtureCaptureID = captureID
        fakeBroker = FakeBrokerServer(socketPath: socketPath) { request in
            switch request.operation {
            case .captureWindow(let captureRequest):
                if captureRequest.windowID == fixtureStaleID {
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .windowNotAvailable, message: "The requested window is not currently available"))
                }
                guard captureRequest.windowID == fixtureWindowID, captureRequest.expectedBundleIdentifier == fixtureBundleID else {
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .windowIdentityChanged, message: "identity changed"))
                }
                return .success(requestID: request.requestID, result: .manifest(manifest))
            case .getCaptureManifest(let manifestRequest):
                guard manifestRequest.captureID == fixtureCaptureID else {
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .resourceNotFound, message: "unknown"))
                }
                return .success(requestID: request.requestID, result: .manifest(manifest))
            case .resolveArtifactResource(let resourceRequest):
                guard resourceRequest.captureID == fixtureCaptureID else {
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .resourceNotFound, message: "unknown"))
                }
                switch resourceRequest.kind {
                case .image:
                    return .success(requestID: request.requestID, result: .artifactResource(ArtifactResourceLocationDTO(path: imagePath, mimeType: "image/png")))
                case .manifest:
                    return .success(requestID: request.requestID, result: .artifactResource(ArtifactResourceLocationDTO(path: manifestPath, mimeType: "application/json")))
                case .ocr:
                    return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .resourceNotFound, message: "ocr not published"))
                }
            default:
                return .failure(requestID: request.requestID, error: BrokerErrorDTO(code: .internalError, message: "unhandled fixture operation"))
            }
        }
        try fakeBroker.start()

        let descriptor = BrokerDescriptor(
            protocolVersion: IPCProtocol.currentVersion,
            socketPath: socketPath,
            guiPID: ProcessInfo.processInfo.processIdentifier,
            expiresAt: Date().addingTimeInterval(3600),
            sessionToken: "test-token"
        )
        try writeTestDescriptor(descriptor, to: mcpDirectory)
    }

    override func tearDown() {
        fakeBroker?.stop()
        fakeBroker = nil
        try? FileManager.default.removeItem(at: tempHome)
        tempHome = nil
        super.tearDown()
    }

    private var helperExecutableURL: URL {
        Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent().appendingPathComponent("BerryShotMCP")
    }

    func testRealStdioTransportHandlesCaptureToolsSuccessAndErrorPathsWithCleanStdout() throws {
        let executableURL = helperExecutableURL
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return XCTFail("BerryShotMCP was not found built at \(executableURL.path); build the package before running this test")
        }

        let process = Process()
        process.executableURL = executableURL
        // `HOME` alone does not isolate `IPCClient`'s default directory on
        // this platform (`FileManager`'s `.applicationSupportDirectory`
        // resolves against the real account regardless — see
        // `main.swift`'s doc comment on `BERRYSHOT_MCP_BASE_DIRECTORY`), so
        // this test uses that explicit override to genuinely point the
        // subprocess's `IPCClient` at the fixture broker/descriptor/artifacts
        // this test just wrote, rather than the real developer machine's
        // actual `~/Library/Application Support/BerryShot/MCP`.
        process.environment = ["HOME": tempHome.path, "BERRYSHOT_MCP_BASE_DIRECTORY": mcpDirectory.path]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutAccumulator = PipeAccumulatorForCaptureTests()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutAccumulator.append(handle.availableData)
        }
        let stderrAccumulator = PipeAccumulatorForCaptureTests()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrAccumulator.append(handle.availableData)
        }

        try process.run()
        defer {
            process.terminate()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
        }

        let stdin = stdinPipe.fileHandleForWriting
        func sendLine(_ json: String) {
            stdin.write(Data((json + "\n").utf8))
        }

        // 1) initialize
        sendLine(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"HelperStdoutProtocolCaptureTests","version":"0.0.1"}}}"#)
        // 2) initialized notification
        sendLine(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        // 3) tools/list — confirms the new tools are advertised over the real transport
        sendLine(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#)
        // 4) capture_window success path
        sendLine(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"capture_window","arguments":{"window_id":\#(windowID),"expected_bundle_id":"\#(bundleID)"}}}"#)
        // 5) capture_window stale-window-id error path (broker rejects it)
        sendLine(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"capture_window","arguments":{"window_id":\#(staleWindowID),"expected_bundle_id":"\#(bundleID)"}}}"#)
        // 6) capture_window argument-validation error path (never touches IPC)
        sendLine(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"capture_window","arguments":{"window_id":\#(windowID),"expected_bundle_id":"\#(bundleID)","preview_max_edge":1}}}"#)
        // 7) get_capture_manifest success path
        sendLine(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_capture_manifest","arguments":{"capture_id":"\#(captureID)"}}}"#)
        // 8) get_capture_manifest for an unknown id — error path
        sendLine(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_capture_manifest","arguments":{"capture_id":"\#(UUID().uuidString)"}}}"#)
        // 9) resources/read for the image — a full binary resource over real stdio
        sendLine(#"{"jsonrpc":"2.0","id":8,"method":"resources/read","params":{"uri":"berryshot://captures/\#(captureID)/image"}}"#)
        // 10) resources/read with a path-traversal-shaped capture id — must be rejected as a protocol error, never read a file
        sendLine(#"{"jsonrpc":"2.0","id":9,"method":"resources/read","params":{"uri":"berryshot://captures/..%2F..%2F..%2Fetc%2Fpasswd/image"}}"#)

        let expectedResponseIDs: Set<Int> = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        let deadline = Date().addingTimeInterval(20)
        while responseCount(in: stdoutAccumulator.snapshot) < expectedResponseIDs.count && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        try? stdin.close()
        process.terminate()
        process.waitUntilExit()
        stdoutAccumulator.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrAccumulator.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        let stdoutData = stdoutAccumulator.snapshot

        // MARK: - Every non-empty stdout line is valid JSON-RPC, no matter which path executed.

        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let lines = stdoutText.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertFalse(lines.isEmpty)

        var parsedResponseIDs: Set<Int> = []
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return XCTFail("stdout contained a line that is not valid JSON (non-protocol bytes on stdout): \(line)")
            }
            XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
            if let idNumber = object["id"] as? Int {
                parsedResponseIDs.insert(idNumber)
            }
        }
        XCTAssertEqual(parsedResponseIDs, expectedResponseIDs)

        let responses = try responseObjects(in: stdoutData)

        // MARK: - tools/list advertises the new tools.

        let toolsListResult = try XCTUnwrap(responses[2]?["result"] as? [String: Any])
        let toolNames = Set((toolsListResult["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
        XCTAssertTrue(toolNames.isSuperset(of: ["capture_window", "capture_application", "get_capture_manifest"]))

        // MARK: - capture_window success: real preview bytes, resource links, snake_case metadata.

        let captureSuccess = try XCTUnwrap(responses[3]?["result"] as? [String: Any])
        XCTAssertNotEqual(captureSuccess["isError"] as? Bool, true, "expected capture_window to succeed against the fixture broker")
        let content = try XCTUnwrap(captureSuccess["content"] as? [[String: Any]])
        XCTAssertTrue(content.contains { ($0["type"] as? String) == "image" }, "expected a bounded inline preview image block")
        XCTAssertTrue(content.contains { ($0["type"] as? String) == "resource_link" }, "expected at least one resource link")
        if let structured = captureSuccess["structuredContent"] as? [String: Any] {
            XCTAssertEqual(structured["capture_id"] as? String, captureID)
            XCTAssertEqual(structured["bundle_id"] as? String, bundleID)
        } else {
            XCTFail("expected structuredContent on a successful capture_window result")
        }

        // MARK: - capture_window stale-window-id error path.

        let captureStaleError = try XCTUnwrap(responses[4]?["result"] as? [String: Any])
        XCTAssertEqual(captureStaleError["isError"] as? Bool, true)

        // MARK: - capture_window argument-validation error path.

        let captureArgError = try XCTUnwrap(responses[5]?["result"] as? [String: Any])
        XCTAssertEqual(captureArgError["isError"] as? Bool, true)

        // MARK: - get_capture_manifest success and error paths.

        let manifestSuccess = try XCTUnwrap(responses[6]?["result"] as? [String: Any])
        XCTAssertNotEqual(manifestSuccess["isError"] as? Bool, true)
        let manifestError = try XCTUnwrap(responses[7]?["result"] as? [String: Any])
        XCTAssertEqual(manifestError["isError"] as? Bool, true)

        // MARK: - resources/read success returns the exact image bytes.

        let imageReadResult = try XCTUnwrap(responses[8]?["result"] as? [String: Any])
        let imageContents = try XCTUnwrap(imageReadResult["contents"] as? [[String: Any]])
        let blobBase64 = try XCTUnwrap(imageContents.first?["blob"] as? String)
        let blobData = try XCTUnwrap(Data(base64Encoded: blobBase64))
        XCTAssertEqual(blobData, imageBytes)

        // MARK: - resources/read with a traversal-shaped id is a protocol error, not file contents.

        let traversalResponse = try XCTUnwrap(responses[9])
        XCTAssertNotNil(traversalResponse["error"], "a malformed capture id in a resource URI must be a JSON-RPC error, never resource contents")

        // MARK: - stderr carried the fixture's internal-error log lines, proving logging did not leak onto stdout.

        _ = stderrAccumulator.snapshot // presence not asserted strictly; absence-from-stdout is the real guarantee above.
    }

    private func responseCount(in data: Data) -> Int {
        (try? responseObjects(in: data))?.count ?? 0
    }

    private func responseObjects(in data: Data) throws -> [Int: [String: Any]] {
        let text = String(data: data, encoding: .utf8) ?? ""
        var result: [Int: [String: Any]] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let idNumber = object["id"] as? Int else { continue }
            result[idNumber] = object
        }
        return result
    }

    private static func pngFixtureData(width: Int, height: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let mutableData = CFDataCreateMutable(nil, 0)!
        let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return mutableData as Data
    }
}

/// `NSLock`-guarded byte accumulator, same shape as `HelperStdoutProtocolTests`'s
/// private one — duplicated (not shared) because that one is `private` to
/// its own file and this test intentionally stays a self-contained
/// end-to-end fixture.
private final class PipeAccumulatorForCaptureTests: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var snapshot: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private final class BundleToken {}
