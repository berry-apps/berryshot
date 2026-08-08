import XCTest
@testable import BerryShot

/// Pure unit tests for the structural/heuristic guards
/// `LiveAXInspecting`/`CaptureBroker` both rely on before ever performing an
/// action (`06-agent-documentation-security.md` section 8's verification
/// checklist: secure field and blocked-role/action rejection).
final class AXInspectionGuardTests: XCTestCase {
    // MARK: - SecureElementGuard

    func testSecureElementGuardDetectsSecureRole() {
        XCTAssertTrue(SecureElementGuard.isSecure(role: "AXSecureTextField", subrole: nil))
    }

    func testSecureElementGuardDetectsSecureSubrole() {
        XCTAssertTrue(SecureElementGuard.isSecure(role: "AXTextField", subrole: "AXSecureTextField"))
    }

    func testSecureElementGuardAllowsOrdinaryTextField() {
        XCTAssertFalse(SecureElementGuard.isSecure(role: "AXTextField", subrole: nil))
    }

    func testSecureElementGuardAllowsButtons() {
        XCTAssertFalse(SecureElementGuard.isSecure(role: "AXButton", subrole: nil))
    }

    // MARK: - DestructiveActionGuard

    func testDestructiveGuardBlocksDeleteBuySend() {
        XCTAssertTrue(DestructiveActionGuard.isBlocked(title: "Delete Account", description: nil))
        XCTAssertTrue(DestructiveActionGuard.isBlocked(title: "Buy Now", description: nil))
        XCTAssertTrue(DestructiveActionGuard.isBlocked(title: "Send Message", description: nil))
    }

    func testDestructiveGuardIsCaseInsensitive() {
        XCTAssertTrue(DestructiveActionGuard.isBlocked(title: "DELETE ALL", description: nil))
        XCTAssertTrue(DestructiveActionGuard.isBlocked(title: "delete all", description: nil))
    }

    func testDestructiveGuardChecksDescriptionToo() {
        XCTAssertTrue(DestructiveActionGuard.isBlocked(title: "OK", description: "Permanently uninstalls the helper"))
    }

    func testDestructiveGuardAllowsOrdinaryControls() {
        XCTAssertFalse(DestructiveActionGuard.isBlocked(title: "Save", description: "Saves the current document"))
        XCTAssertFalse(DestructiveActionGuard.isBlocked(title: "Enable Notifications", description: nil))
        XCTAssertFalse(DestructiveActionGuard.isBlocked(title: nil, description: nil))
    }

    func testDestructiveGuardMatchesEveryLockedKeywordFromTheRiskTable() {
        // `06-agent-documentation-security.md` section 5's risk table lists
        // these verbatim under "External side effect"/"Destructive". A
        // future accidental edit that drops one of these from
        // `DestructiveActionGuard.blockedKeywords` fails this test instead
        // of silently narrowing the guard.
        let expectedKeywords = [
            "delete", "remove", "erase", "uninstall", "reset", "revoke",
            "purchase", "buy", "pay", "subscribe",
            "send", "publish", "upload", "install", "download"
        ]
        for keyword in expectedKeywords {
            XCTAssertTrue(DestructiveActionGuard.isBlocked(title: "\(keyword.capitalized) now", description: nil), "expected '\(keyword)' to be blocked")
        }
    }

    // MARK: - AXAutomationTextSanitizer

    func testTextSanitizerStripsControlCharacters() {
        let sanitized = AXAutomationTextSanitizer.sanitize("Hello\u{0007}World")
        XCTAssertEqual(sanitized, "HelloWorld")
    }

    func testTextSanitizerBoundsLength() {
        let long = String(repeating: "a", count: AXAutomationTextSanitizer.maxLength + 100)
        let sanitized = AXAutomationTextSanitizer.sanitize(long)
        XCTAssertEqual(sanitized.count, AXAutomationTextSanitizer.maxLength)
    }
}
