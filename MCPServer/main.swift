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

let ipcClient = IPCClient(log: log)
let server = await MCPServerFactory.makeServer(ipcClient: ipcClient, log: log)
let transport = StdioTransport(logger: log)

do {
    try await server.start(transport: transport)
    await server.waitUntilCompleted()
} catch {
    log.error("BerryShotMCP exiting after a fatal transport error", metadata: ["error": "\(error)"])
    exit(1)
}
