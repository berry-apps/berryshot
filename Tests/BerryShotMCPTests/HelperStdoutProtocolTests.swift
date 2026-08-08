import XCTest
#if canImport(Darwin)
import Darwin
#endif

/// `NSLock`-guarded byte accumulator for `Pipe.fileHandleForReading.readabilityHandler`,
/// which fires on a background thread. `@unchecked Sendable` is safe here
/// because `append`/`snapshot` are the only access points and both hold
/// `lock` for their entire body.
private final class PipeAccumulator: @unchecked Sendable {
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

/// End-to-end test spawning the real, built `BerryShotMCP` binary as a
/// subprocess exactly the way an MCP client (Codex, Claude Code) would,
/// and talking newline-delimited JSON-RPC over its stdin/stdout — the
/// actual `05-mcp-server-contract.md` transport, not `InMemoryTransport`.
///
/// This is the test backing WP6's most safety-critical verification bullet
/// (`08-implementation-work-packages.md`): "Stdout contains no non-protocol
/// bytes even when errors/logs occur." No GUI/broker is running in this
/// test environment, so every tool call the test makes is guaranteed to
/// exercise the helper's *error* path (`berryshot_unavailable`) — the
/// scenario most likely to accidentally leak a `print()`/stack trace onto
/// stdout — while a genuinely malformed tool argument exercises the
/// argument-validation error path without even touching IPC.
final class HelperStdoutProtocolTests: XCTestCase {
    private var tempHome: URL!

    override func setUp() {
        super.setUp()
        // This test writes to the subprocess's stdin pipe from the test
        // process itself. If the helper has already exited (e.g. it hit an
        // early error) by the time a later `sendLine` runs, that write hits
        // a reader-less pipe and raises `SIGPIPE` — whose default
        // disposition kills the entire `swift test` process, not just this
        // test. Ignore it process-wide so the write fails with `EPIPE`
        // (an ordinary, catchable condition) instead.
        signal(SIGPIPE, SIG_IGN)
        tempHome = FileManager.default.temporaryDirectory.appendingPathComponent("bsmcp-home-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempHome)
        tempHome = nil
        super.tearDown()
    }

    private var helperExecutableURL: URL {
        // BerryShotMCP is built as a sibling product next to this test
        // bundle in `.build/<triple>/<configuration>/`.
        Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent().appendingPathComponent("BerryShotMCP")
    }

    func testStdoutCarriesOnlyValidJSONRPCLinesIncludingDuringToolErrors() throws {
        let executableURL = helperExecutableURL
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return XCTFail("BerryShotMCP was not found built at \(executableURL.path); build the package before running this test")
        }

        let process = Process()
        process.executableURL = executableURL
        // Redirect HOME so IPCClient's `~/Library/Application Support/BerryShot/MCP`
        // resolves to an empty, isolated directory: no descriptor exists,
        // so every IPC-backed tool call deterministically fails with
        // berryshot_unavailable regardless of what else is running on this
        // machine.
        process.environment = ["HOME": tempHome.path]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutAccumulator = PipeAccumulator()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutAccumulator.append(handle.availableData)
        }
        let stderrAccumulator = PipeAccumulator()
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
        sendLine(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"HelperStdoutProtocolTests","version":"0.0.1"}}}"#)
        // 2) initialized notification (no id — no response expected)
        sendLine(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        // 3) tools/list
        sendLine(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#)
        // 4) tools/call permissions_status — exercises the IPC-unavailable error path
        sendLine(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"permissions_status","arguments":{}}}"#)
        // 5) tools/call list_applications with an out-of-range limit — exercises
        //    the argument-validation error path (never touches IPC at all)
        sendLine(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_applications","arguments":{"limit":0}}}"#)
        // 6) a malformed/unknown-method request — exercises a JSON-RPC protocol error
        sendLine(#"{"jsonrpc":"2.0","id":5,"method":"not/a/real/method","params":{}}"#)

        // Expect 4 response lines: ids 1, 2, 3, 4, 5 (the notification gets none).
        let deadline = Date().addingTimeInterval(15)
        while responseCount(in: stdoutAccumulator.snapshot) < 5 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        try? stdin.close()
        process.terminate()
        process.waitUntilExit()
        // Drain anything written between the last poll and process exit.
        stdoutAccumulator.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrAccumulator.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        let stdoutData = stdoutAccumulator.snapshot
        let stderrData = stderrAccumulator.snapshot

        // MARK: - The core assertion: every non-empty stdout line is valid JSON-RPC.

        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let lines = stdoutText.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertFalse(lines.isEmpty, "expected at least one JSON-RPC response line on stdout")

        var parsedResponseIDs: Set<Int> = []
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return XCTFail("stdout contained a line that is not valid JSON (non-protocol bytes on stdout): \(line)")
            }
            XCTAssertEqual(object["jsonrpc"] as? String, "2.0", "every stdout line must be a JSON-RPC 2.0 message")
            if let idNumber = object["id"] as? Int {
                parsedResponseIDs.insert(idNumber)
            }
        }

        XCTAssertEqual(parsedResponseIDs, [1, 2, 3, 4, 5], "expected exactly one JSON-RPC response per request id")

        // MARK: - Tool-call error results still carry no non-protocol bytes,
        // and stay shaped like isError:true tool results rather than raw
        // exceptions.

        let responsesByID = try responseObjects(in: stdoutData)
        let permissionsStatusResponse = try XCTUnwrap(responsesByID[3])
        let permissionsResult = try XCTUnwrap(permissionsStatusResponse["result"] as? [String: Any])
        XCTAssertEqual(permissionsResult["isError"] as? Bool, true, "permissions_status must fail cleanly with isError:true when no broker is reachable")

        let listApplicationsResponse = try XCTUnwrap(responsesByID[4])
        let listApplicationsResult = try XCTUnwrap(listApplicationsResponse["result"] as? [String: Any])
        XCTAssertEqual(listApplicationsResult["isError"] as? Bool, true, "list_applications with limit:0 must be rejected as isError:true")

        // MARK: - Logging went to stderr, proving the helper actually did
        // log something about the unreachable broker rather than staying
        // silent (which would make this test meaningless), and that this
        // logging did not end up mixed into stdout.

        XCTAssertFalse(stderrData.isEmpty, "expected the helper to log the unreachable-broker condition to stderr")
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
}

private final class BundleToken {}
