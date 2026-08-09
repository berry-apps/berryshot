import BerryShotIPC

/// Conversions between the wire-level enums `BerryShotIPC` defines
/// (`Shared/IPC/CaptureModels.swift`, which cannot import the `BerryShot`
/// target) and the real redaction enums those wire values stand in for
/// (`Sources/Redaction/RedactionModels.swift`, `Sources/Capture/CaptureContext.swift`,
/// `Sources/Capture/CaptureArtifact.swift`). Exhaustive `switch`es rather
/// than `init?(rawValue:)` round-tripping so a future case added to either
/// side fails to compile here instead of silently mapping to the wrong
/// value.
extension IPCRedactionPolicy {
    var corePolicy: RedactionPolicy {
        switch self {
        case .none: return .none
        case .suggest: return .suggest
        case .required: return .required
        }
    }
}

extension IPCRedactionStyle {
    var coreStyle: RedactionStyle {
        switch self {
        case .blur: return .blur
        case .pixelate: return .pixelate
        case .solid: return .solid
        }
    }
}

extension IPCRedactionStatus {
    init(coreStatus: RedactionStatus) {
        switch coreStatus {
        case .notRequested: self = .notRequested
        case .clean: self = .clean
        case .applied: self = .applied
        case .needsReview: self = .needsReview
        case .unavailable: self = .unavailable
        }
    }
}
