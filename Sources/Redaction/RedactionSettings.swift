import Foundation
import SwiftUI

/// Persisted user choice for the redaction contract in
/// `04-sensitive-redaction-spec.md`. WP4 has no automatic AX/Vision detection
/// yet; this setting only controls manual-region behavior and the honest
/// `needsReview` fallback described in that spec's section 2.
///
/// Not named in `02-target-architecture.md`'s recommended file list, which
/// only anticipates detection/rendering domain files. It is added here,
/// beside the other new `Redaction` module files, because Privacy settings
/// needs somewhere to persist the policy/style choice and `StorageConfiguration`
/// (`Core/StorageConfiguration.swift`) is this codebase's existing precedent
/// for an `@AppStorage`-backed, `@MainActor` settings singleton.
@MainActor
public final class RedactionSettings: ObservableObject {
    public static let shared = RedactionSettings()

    /// Locked default per `10-decisions-risks-open-questions.md` section 4:
    /// "GUI defaults to `suggest + blur`".
    @AppStorage("redaction_policy") public var policy: RedactionPolicy = .suggest
    @AppStorage("redaction_style") public var style: RedactionStyle = .blur

    // MARK: - WP5: automatic detection categories
    //
    // Defaults match `10-decisions-risks-open-questions.md` section 4 point 3
    // and `04-sensitive-redaction-spec.md` section 1: "Secure AX fields and
    // validated card/token/private-key patterns are enabled by default.
    // Email and phone detection are opt-in."

    @AppStorage("redaction_detect_secure_fields") public var detectSecureFields: Bool = true
    @AppStorage("redaction_detect_card_numbers") public var detectCardNumbers: Bool = true
    @AppStorage("redaction_detect_api_tokens") public var detectAPITokens: Bool = true
    @AppStorage("redaction_detect_email") public var detectEmail: Bool = false
    @AppStorage("redaction_detect_phone_numbers") public var detectPhoneNumbers: Bool = false
    @AppStorage("redaction_custom_terms_case_sensitive") public var customTermsCaseSensitive: Bool = false

    /// User-configured literal terms to redact, stored locally as JSON
    /// (UserDefaults has no native `[String]` `@AppStorage` support). Never
    /// logged: `SensitiveContentDetector`/`SensitiveTextClassifier` only ever
    /// use these to test for a substring match and report a category hit —
    /// the term itself never appears in a `RedactionRegion`, a log line, or
    /// any other persisted value.
    @Published public var customTerms: [String] {
        didSet { persistCustomTerms() }
    }

    private static let customTermsDefaultsKey = "redaction_custom_terms"

    private init() {
        self.customTerms = Self.loadCustomTerms()
    }

    public func addCustomTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customTerms.contains(trimmed) else { return }
        customTerms.append(trimmed)
    }

    public func removeCustomTerm(at offsets: IndexSet) {
        customTerms.remove(atOffsets: offsets)
    }

    private static func loadCustomTerms() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: customTermsDefaultsKey),
              let terms = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return terms
    }

    private func persistCustomTerms() {
        guard let data = try? JSONEncoder().encode(customTerms) else { return }
        UserDefaults.standard.set(data, forKey: Self.customTermsDefaultsKey)
    }

    /// The set of automatically detected categories currently enabled by the
    /// user, plus `.manual` (always active — manual regions are never
    /// gated by a detection toggle).
    public var enabledAutomaticCategories: Set<SensitiveCategory> {
        var categories: Set<SensitiveCategory> = [.manual]
        if detectSecureFields { categories.insert(.secureField) }
        if detectCardNumbers { categories.insert(.creditCard) }
        if detectAPITokens { categories.insert(.apiToken) }
        if detectEmail { categories.insert(.email) }
        if detectPhoneNumbers { categories.insert(.phoneNumber) }
        if !customTerms.isEmpty { categories.insert(.customTerm) }
        return categories
    }

    /// Snapshots the current settings into the value type
    /// `SensitiveContentDetector`/`SensitiveContentPolicyRedactor` consume.
    /// Called once per capture (from a non-MainActor context) rather than
    /// holding a live reference to this `@MainActor` object across the
    /// capture pipeline.
    public func detectionConfiguration() -> SensitiveDetectionConfiguration {
        SensitiveDetectionConfiguration(
            enabledCategories: enabledAutomaticCategories,
            customTerms: customTerms,
            customTermsCaseSensitive: customTermsCaseSensitive,
            style: style
        )
    }
}
