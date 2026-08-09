import Foundation

/// One deterministic classifier hit within a single OCR observation's text.
/// Carries no copy of the matched substring or the source text — only a
/// category and confidence — so a caller can never accidentally log or
/// persist recognized secret content by holding on to a match. This mirrors
/// `RedactionRegion`'s own "never store recognized secret content" rule one
/// layer earlier, at detection time rather than only at the region model.
public struct ClassifiedTextMatch: Sendable, Equatable {
    public let category: SensitiveCategory
    public let confidence: Double

    public init(category: SensitiveCategory, confidence: Double) {
        self.category = category
        self.confidence = confidence
    }
}

/// Conservative, deterministic text classifiers per
/// `04-sensitive-redaction-spec.md` section 3. Every classifier here is
/// intentionally narrow: the spec explicitly forbids classifying ordinary
/// UUIDs, IP addresses, or file paths, because false positives are costly
/// for technical documentation screenshots. When in doubt, a classifier
/// below returns no match rather than a low-confidence guess.
///
/// Classification runs per OCR observation (typically one line of
/// recognized text), not on substrings within a line. Vision's bounding
/// boxes are already only approximate at the substring level (see
/// `RedactionCoordinateMapper`), so masking the whole matched line's box is
/// the same "approximate, not pixel-perfect" tradeoff the spec accepts
/// explicitly rather than a new one introduced here.
public enum SensitiveTextClassifier {
    // MARK: - Luhn

    /// Validates a candidate digit string using the Luhn checksum (ISO/IEC
    /// 7812-1), the standard check digit algorithm for payment card numbers.
    /// Non-digit characters (spaces, dashes) are ignored so callers can pass
    /// the matched text as written on screen.
    public static func passesLuhnCheck(_ candidate: String) -> Bool {
        let digits = candidate.compactMap(\.wholeNumberValue)
        guard digits.count >= 12, digits.count <= 19 else { return false }

        var sum = 0
        var alternate = false
        for digit in digits.reversed() {
            var value = digit
            if alternate {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
            alternate.toggle()
        }
        return sum % 10 == 0
    }

    // MARK: - Regex-backed detectors

    private static let emailRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9][A-Za-z0-9._%+-]*@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"#
    )

    /// Digit-group runs long enough to be a card number once separators are
    /// stripped (13-19 digits, per ISO/IEC 7812).
    private static let cardCandidateRegex = try! NSRegularExpression(
        pattern: #"\d(?:[ -]?\d){11,18}"#
    )

    private static let phoneCandidateRegex = try! NSRegularExpression(
        pattern: #"[+0-9(][0-9()\s.-]{5,18}[0-9)]"#
    )
    private static let ipv4Regex = try! NSRegularExpression(pattern: #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#)
    private static let isoDateRegex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
    /// Standard 8-4-4-4-12 hex UUID shape. A UUID's dash-separated hex groups
    /// can contain a trailing all-digit segment (for example
    /// `...-A716-446655440000`) that would otherwise look like a formatted,
    /// separator-containing phone number to the candidate regex above, so
    /// any UUID-shaped substring is stripped from the text before phone
    /// candidates are searched for at all.
    private static let uuidRegex = try! NSRegularExpression(
        pattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
    )

    /// Common API/token prefixes named explicitly in the spec: OpenAI,
    /// GitHub, AWS access key IDs, bearer tokens, and private key headers.
    private static let tokenRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"sk-[A-Za-z0-9_-]{20,}"#), // OpenAI
        try! NSRegularExpression(pattern: #"gh[pousr]_[A-Za-z0-9]{30,}"#), // GitHub fine-grained/classic PATs
        try! NSRegularExpression(pattern: #"github_pat_[A-Za-z0-9_]{20,}"#), // GitHub fine-grained PAT (long form)
        try! NSRegularExpression(pattern: #"AKIA[0-9A-Z]{16}"#), // AWS access key ID
        try! NSRegularExpression(pattern: #"(?i)bearer\s+[A-Za-z0-9\-_.=]{10,}"#), // Bearer token
        try! NSRegularExpression(pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#) // Private key header
    ]

    private static func fullRange(_ text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }

    public static func containsEmail(_ text: String) -> Bool {
        emailRegex.firstMatch(in: text, range: fullRange(text)) != nil
    }

    public static func containsAPIToken(_ text: String) -> Bool {
        tokenRegexes.contains { $0.firstMatch(in: text, range: fullRange(text)) != nil }
    }

    /// Finds digit-group runs of card-number length and Luhn-validates each
    /// one. A regex-shaped run alone is not enough evidence; only a
    /// Luhn-valid run is classified, per the spec's explicit "validated by
    /// Luhn" requirement.
    public static func containsValidatedCardNumber(_ text: String) -> Bool {
        let ns = text as NSString
        let matches = cardCandidateRegex.matches(in: text, range: fullRange(text))
        for match in matches {
            let candidate = ns.substring(with: match.range)
            if passesLuhnCheck(candidate) { return true }
        }
        return false
    }

    /// Conservative phone-number detection. A candidate must be a
    /// digit/punctuation run with 7-15 digits (E.164's own maximum) once
    /// separators are stripped, and must either start with `+` or contain at
    /// least one formatting separator — a bare unformatted digit run is
    /// deliberately not enough evidence, since arbitrary technical IDs are
    /// common in screenshots and the spec asks for conservative rules over
    /// completeness. IPv4 addresses and ISO-8601 dates are excluded
    /// explicitly because both can otherwise satisfy the digit/separator
    /// shape above; this is a known, intentionally narrow heuristic, not a
    /// claim of complete phone-number coverage.
    public static func containsConservativePhoneNumber(_ text: String) -> Bool {
        let withoutUUIDs = uuidRegex.stringByReplacingMatches(in: text, range: fullRange(text), withTemplate: "")
        let ns = withoutUUIDs as NSString
        let matches = phoneCandidateRegex.matches(in: withoutUUIDs, range: fullRange(withoutUUIDs))
        for match in matches {
            let candidate = ns.substring(with: match.range).trimmingCharacters(in: .whitespaces)
            let digitCount = candidate.filter(\.isNumber).count
            guard digitCount >= 7, digitCount <= 15 else { continue }

            let candidateRange = NSRange(location: 0, length: (candidate as NSString).length)
            guard ipv4Regex.firstMatch(in: candidate, range: candidateRange) == nil else { continue }
            guard isoDateRegex.firstMatch(in: candidate, range: candidateRange) == nil else { continue }

            let hasSeparator = candidate.contains { " -.()".contains($0) }
            guard candidate.hasPrefix("+") || hasSeparator else { continue }
            return true
        }
        return false
    }

    /// Matches a user-configured literal term as a plain substring (never a
    /// regex — an arbitrary user-typed term may contain regex metacharacters
    /// that should be matched literally), case-sensitively or insensitively
    /// per the caller's setting.
    public static func containsCustomTerm(_ text: String, term: String, caseSensitive: Bool) -> Bool {
        guard !term.isEmpty else { return false }
        return text.range(of: term, options: caseSensitive ? [] : .caseInsensitive) != nil
    }

    // MARK: - Composition

    /// Confidence assigned to each category's match. AX-sourced categories
    /// are not scored here; they carry `1.0` at the point they are created
    /// (see `SensitiveContentDetector`) because they come from a structural
    /// AX fact, not an inferred pattern match.
    private static func confidence(for category: SensitiveCategory) -> Double {
        switch category {
        case .customTerm: return 1.0
        case .creditCard: return 0.9
        case .apiToken: return 0.85
        case .email: return 0.7
        case .phoneNumber: return 0.6
        case .secureField, .manual: return 1.0
        }
    }

    /// Runs every enabled classifier against one OCR observation's text and
    /// returns every distinct category that matched. `enabledCategories`
    /// gates which classifiers run at all, so a disabled category (for
    /// example email/phone, which default to opt-in per
    /// `10-decisions-risks-open-questions.md` section 4) never contributes a
    /// match regardless of the text's content.
    public static func matches(
        in text: String,
        enabledCategories: Set<SensitiveCategory>,
        customTerms: [String],
        customTermsCaseSensitive: Bool
    ) -> [ClassifiedTextMatch] {
        guard !text.isEmpty else { return [] }
        var found: [ClassifiedTextMatch] = []

        if enabledCategories.contains(.creditCard), containsValidatedCardNumber(text) {
            found.append(ClassifiedTextMatch(category: .creditCard, confidence: confidence(for: .creditCard)))
        }
        if enabledCategories.contains(.apiToken), containsAPIToken(text) {
            found.append(ClassifiedTextMatch(category: .apiToken, confidence: confidence(for: .apiToken)))
        }
        if enabledCategories.contains(.email), containsEmail(text) {
            found.append(ClassifiedTextMatch(category: .email, confidence: confidence(for: .email)))
        }
        if enabledCategories.contains(.phoneNumber), containsConservativePhoneNumber(text) {
            found.append(ClassifiedTextMatch(category: .phoneNumber, confidence: confidence(for: .phoneNumber)))
        }
        if enabledCategories.contains(.customTerm) {
            let matchedAnyTerm = customTerms.contains {
                containsCustomTerm(text, term: $0, caseSensitive: customTermsCaseSensitive)
            }
            if matchedAnyTerm {
                found.append(ClassifiedTextMatch(category: .customTerm, confidence: confidence(for: .customTerm)))
            }
        }

        return found
    }
}
