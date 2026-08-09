import Foundation
import Logging
import MCP
import BerryShotIPC
#if canImport(Darwin)
import Darwin
#endif

// `SO_NOSIGPIPE` (set on the broker IPC socket in `IPCClient`) only covers
// that one socket. Stdout/stdin are plain pipes when an MCP client (Codex,
// Claude Code) spawns this helper, and writing to a pipe whose reader has
// already gone away raises `SIGPIPE`, whose default disposition kills the
// whole process. A client that disconnects mid-response must not be able
// to crash this helper. Ignore it process-wide so writes fail with `EPIPE`
// (an ordinary error) instead.
signal(SIGPIPE, SIG_IGN)

// MUST happen before any Logger is constructed or any MCP type touches
// stdout: MCP stdout must carry only protocol bytes
// (`01-scope-current-state.md` section 6; `05-mcp-server-contract.md`
// section 9 verification: "Stdout parser sees only MCP messages; inject
// logs and confirm they go elsewhere").
let log = HelperLogging.bootstrap(label: "com.tan.berryshot.mcp")

// Test-only override seam: `FileManager`'s `.applicationSupportDirectory`
// resolves against the real logged-in user's home directory regardless of
// a `HOME` environment variable override on this platform (verified
// directly; a subprocess launched with a custom `HOME` still resolves
// `~/Library/Application Support` to the real account's home). Integration
// tests that need a genuinely isolated broker directory — spawning this
// real binary against a fake broker, as `HelperStdoutProtocolCaptureTests`
// does — set this variable instead.
//
// This must not exist in a release build: the broker descriptor this
// points at carries the IPC session secret that authenticates the whole
// broker<->helper channel (see `05-mcp-server-contract.md` §2). An
// unconditional env-var redirect would let anything that controls this
// process's launch environment (a tampered MCP client config, a malicious
// parent process) point the helper at a forged broker and spoof capture
// results — defeating the same-UID/session-secret protections entirely.
// `#if DEBUG` compiles this seam out of `swift build -c release`, which is
// what `build_app.sh` ships, so production behavior
// (`IPCClient.defaultBaseDirectory`) is unconditional there.
#if DEBUG
let ipcBaseDirectoryOverride = ProcessInfo.processInfo.environment["BERRYSHOT_MCP_BASE_DIRECTORY"]
    .map { URL(fileURLWithPath: $0, isDirectory: true) }
#else
let ipcBaseDirectoryOverride: URL? = nil
#endif
let ipcClient = ipcBaseDirectoryOverride.map { IPCClient(baseDirectory: $0, log: log) } ?? IPCClient(log: log)
let server = await MCPServerFactory.makeServer(ipcClient: ipcClient, log: log)
let transport = StdioTransport(logger: log)

do {
    try await server.start(transport: transport)
    await server.waitUntilCompleted()
} catch {
    log.error("BerryShotMCP exiting after a fatal transport error", metadata: ["error": "\(error)"])
    exit(1)
}
