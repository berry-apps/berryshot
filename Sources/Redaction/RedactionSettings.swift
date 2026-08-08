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

    private init() {}
}
