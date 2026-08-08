import Foundation
import Logging

/// Bootstraps the swift-log backend the pinned MCP SDK (and this helper's
/// own code) use, pinned to stderr. MCP stdout must carry only protocol
/// bytes (`01-scope-current-state.md` section 6 anti-pattern guard: "Do not
/// write logs to MCP stdout"); `StdioTransport` already defaults to a
/// no-op logger when none is supplied, but this helper passes an explicit
/// stderr-backed logger everywhere so no future code path can silently
/// default to `StreamLogHandler.standardOutput` instead.
///
/// Call this exactly once, before constructing any `Logger` or the MCP
/// `Server`/`StdioTransport`.
public enum HelperLogging {
    public static func bootstrap(label: String, level: Logger.Level = .info) -> Logger {
        LoggingSystem.bootstrap { handlerLabel in
            var handler = StreamLogHandler.standardError(label: handlerLabel)
            handler.logLevel = level
            return handler
        }
        return Logger(label: label)
    }
}
