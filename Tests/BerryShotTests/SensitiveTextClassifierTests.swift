import XCTest
@testable import BerryShot

/// Positive/negative classifier suite and Luhn validation, per WP5's
/// verification checklist in `08-implementation-work-packages.md`. Every
/// "real-looking" credential below is either a well-known public test value
/// (Visa/Mastercard test numbers, AWS's own published `AKIAIOSFODNN7EXAMPLE`)
/// or an obviously fabricated string — never a real secret, per the spec's
/// "programmatically generated ... fake secrets; never commit real
/// credentials" rule.
final class SensitiveTextClassifierTests: XCTestCase {
    private let allCategories: Set<SensitiveCategory> = [.email, .phoneNumber, .creditCard, .apiToken, .customTerm]

    // MARK: - Luhn

    func testLuhnAcceptsKnownValidTestCardNumbers() {
        XCTAssertTrue(SensitiveTextClassifier.passesLuhnCheck("4111111111111111"), "well-known Visa test number")
        XCTAssertTrue(SensitiveTextClassifier.passesLuhnCheck("5500005555555559"), "well-known Mastercard test number")
        XCTAssertTrue(SensitiveTextClassifier.passesLuhnCheck("4111 1111 1111 1111"), "spaces must be ignored")
        XCTAssertTrue(SensitiveTextClassifier.passesLuhnCheck("4111-1111-1111-1111"), "dashes must be ignored")
    }

    func testLuhnRejectsInvalidChecksumsAndOutOfRangeLengths() {
        XCTAssertFalse(SensitiveTextClassifier.passesLuhnCheck("4111111111111112"), "corrupted checksum digit")
        XCTAssertFalse(SensitiveTextClassifier.passesLuhnCheck("123456789012"), "too short for a real PAN family, and fails checksum")
        XCTAssertFalse(SensitiveTextClassifier.passesLuhnCheck(""), "empty input")
        XCTAssertFalse(SensitiveTextClassifier.passesLuhnCheck("abcd"), "non-numeric input")
    }

    // MARK: - Email

    func testEmailPositive() {
        XCTAssertTrue(SensitiveTextClassifier.containsEmail("Contact: john.doe@example.com for access"))
        XCTAssertTrue(SensitiveTextClassifier.containsEmail("first.last+tag@sub.example.co.uk"))
    }

    func testEmailNegative() {
        XCTAssertFalse(SensitiveTextClassifier.containsEmail("not-an-email"))
        XCTAssertFalse(SensitiveTextClassifier.containsEmail("user@"))
        XCTAssertFalse(SensitiveTextClassifier.containsEmail("Build version 4.2.1"))
    }

    // MARK: - Phone (conservative)

    func testPhonePositive() {
        XCTAssertTrue(SensitiveTextClassifier.containsConservativePhoneNumber("Call +1 415-555-0132 for support"))
        XCTAssertTrue(SensitiveTextClassifier.containsConservativePhoneNumber("Office: (415) 555-0132"))
        XCTAssertTrue(SensitiveTextClassifier.containsConservativePhoneNumber("415-555-0132"))
    }

    func testPhoneNegativeRejectsUnformattedDigitsIPsAndDates() {
        // Conservative by design: a bare, unformatted digit run is not
        // enough evidence on its own (see the classifier's doc comment).
        XCTAssertFalse(SensitiveTextClassifier.containsConservativePhoneNumber("Ticket 4155550132 was closed"))
        // IPv4 addresses must never be classified as phone numbers (or any
        // other category) per the spec's explicit "do not classify IP
        // addresses" rule.
        XCTAssertFalse(SensitiveTextClassifier.containsConservativePhoneNumber("Server bound to 192.168.1.1"))
        // ISO-8601 dates are digit+separator runs of plausible phone length
        // and must not false-positive.
        XCTAssertFalse(SensitiveTextClassifier.containsConservativePhoneNumber("Released on 2026-08-09"))
        XCTAssertFalse(SensitiveTextClassifier.containsConservativePhoneNumber("12345"))
    }

    // MARK: - Credit card (Luhn-gated)

    func testCreditCardPositive() {
        XCTAssertTrue(SensitiveTextClassifier.containsValidatedCardNumber("Card on file: 4111 1111 1111 1111"))
        XCTAssertTrue(SensitiveTextClassifier.containsValidatedCardNumber("4111111111111111"))
    }

    func testCreditCardNegativeRequiresLuhnValidity() {
        // Same shape as a real PAN, but the checksum is wrong - a
        // digit-shaped run alone must not be enough.
        XCTAssertFalse(SensitiveTextClassifier.containsValidatedCardNumber("Order #4111 1111 1111 1112"))
        XCTAssertFalse(SensitiveTextClassifier.containsValidatedCardNumber("Reference 12345"))
    }

    // MARK: - API/token prefixes

    func testAPITokenPositive() {
        XCTAssertTrue(SensitiveTextClassifier.containsAPIToken("OPENAI_API_KEY=sk-ABCDEFGHIJKLMNOPQRSTUVWX1234"))
        XCTAssertTrue(SensitiveTextClassifier.containsAPIToken("token: ghp_1234567890abcdefghij1234567890ABCDEFwxyz"))
        XCTAssertTrue(SensitiveTextClassifier.containsAPIToken("github_pat_11ABCDEFG0abcdefghijklmnopqrstuvwxyz"))
        // AWS's own publicly documented example access key ID.
        XCTAssertTrue(SensitiveTextClassifier.containsAPIToken("aws_access_key_id = AKIAIOSFODNN7EXAMPLE"))
        XCTAssertTrue(SensitiveTextClassifier.containsAPIToken("Authorization: Bearer abcdef1234567890XYZuvw"))
        XCTAssertTrue(SensitiveTextClassifier.containsAPIToken("-----BEGIN RSA PRIVATE KEY-----"))
        XCTAssertTrue(SensitiveTextClassifier.containsAPIToken("-----BEGIN OPENSSH PRIVATE KEY-----"))
    }

    func testAPITokenNegative() {
        XCTAssertFalse(SensitiveTextClassifier.containsAPIToken("sk-short"))
        XCTAssertFalse(SensitiveTextClassifier.containsAPIToken("ghp_tooshort"))
        XCTAssertFalse(SensitiveTextClassifier.containsAPIToken("This function returns a bearer of good news."))
        XCTAssertFalse(SensitiveTextClassifier.containsAPIToken("Just some ordinary log output"))
    }

    // MARK: - Custom terms

    func testCustomTermMatchesCaseInsensitivelyByDefault() {
        XCTAssertTrue(SensitiveTextClassifier.containsCustomTerm("Project CODENAME-FALCON status", term: "codename-falcon", caseSensitive: false))
    }

    func testCustomTermCaseSensitiveRequiresExactCase() {
        XCTAssertFalse(SensitiveTextClassifier.containsCustomTerm("Project codename-falcon status", term: "CODENAME-FALCON", caseSensitive: true))
        XCTAssertTrue(SensitiveTextClassifier.containsCustomTerm("Project CODENAME-FALCON status", term: "CODENAME-FALCON", caseSensitive: true))
    }

    func testCustomTermEmptyTermNeverMatches() {
        XCTAssertFalse(SensitiveTextClassifier.containsCustomTerm("anything at all", term: "", caseSensitive: false))
    }

    // MARK: - Explicitly excluded categories (anti-pattern guard)

    /// Spec section 3: "Do not classify ordinary UUIDs, IP addresses, or
    /// file paths by default without product approval."
    func testUUIDsIPsAndFilePathsAreNeverClassifiedByAnyEnabledCategory() {
        let uuidLine = "Trace ID: 550E8400-E29B-41D4-A716-446655440000"
        let ipLine = "Bound to 10.0.0.42 on port 8080"
        let pathLine = "Loaded config from /Users/example/Library/Application Support/BerryShot/config.json"

        for line in [uuidLine, ipLine, pathLine] {
            let matches = SensitiveTextClassifier.matches(
                in: line,
                enabledCategories: allCategories,
                customTerms: [],
                customTermsCaseSensitive: false
            )
            XCTAssertTrue(matches.isEmpty, "\"\(line)\" must not match any classifier, got \(matches)")
        }
    }

    // MARK: - Composition

    func testMatchesReturnsOnlyEnabledCategories() {
        let text = "Email me at john.doe@example.com or call 415-555-0132"
        let emailOnly = SensitiveTextClassifier.matches(
            in: text,
            enabledCategories: [.email],
            customTerms: [],
            customTermsCaseSensitive: false
        )
        XCTAssertEqual(emailOnly.map(\.category), [.email])

        let none = SensitiveTextClassifier.matches(
            in: text,
            enabledCategories: [],
            customTerms: [],
            customTermsCaseSensitive: false
        )
        XCTAssertTrue(none.isEmpty)
    }
}
