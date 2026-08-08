import Foundation
import os

/// The audit log `06-agent-documentation-security.md` section 6 requires:
/// "Audit log stores timestamp, client, tool, target IDs, outcome, and
/// redaction status; never sensitive text or raw image bytes." Every
/// parameter here is a stable identifier (bundle ID, capture ID, session ID,
/// error code) or an enum-shaped value — never free-form user text, AX
/// title/description strings, OCR text, or image bytes, so there is no way
/// to accidentally log recognized sensitive content through this type.
///
/// Backed by `os.Logger` rather than a bespoke file: the timestamp, process,
/// and durability guarantees unified logging already provides are exactly
/// what an audit trail needs, and it never touches MCP stdout
/// (`02-target-architecture.md` section 2: "Log only to stderr or unified
/// logging").
public enum DocumentationAuditLog {
    private static let logger = Logger(subsystem: "com.tan.berryshot", category: "DocumentationAudit")

    public static func record(
        tool: String,
        sessionID: String?,
        target: String,
        outcome: String,
        redactionStatus: String? = nil,
        client: String = "unknown"
    ) {
        logger.notice(
            "mcp_audit tool=\(tool, privacy: .public) session=\(sessionID ?? "-", privacy: .public) target=\(target, privacy: .public) outcome=\(outcome, privacy: .public) redaction=\(redactionStatus ?? "n/a", privacy: .public) client=\(client, privacy: .public)"
        )
    }
}
