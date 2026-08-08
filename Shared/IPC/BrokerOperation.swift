import Foundation

/// The bounded set of operations `CaptureBroker` accepts in this work
/// package: read-only discovery plus a connectivity/lifecycle pair. Capture
/// and redaction operations are explicitly out of scope for WP6
/// (`08-implementation-work-packages.md` WP6 goal: "without yet exposing
/// full production tools").
///
/// `Codable` conformance is written by hand rather than relying on Swift's
/// automatic enum-with-associated-values synthesis: the wire format for a
/// versioned cross-process protocol must be a format this file defines and
/// controls, not whatever the compiler happens to synthesize for a given
/// toolchain.
public enum BrokerOperation: Sendable, Equatable {
    /// Cheap liveness/handshake check; does not touch ScreenCaptureKit or AX.
    case ping
    case permissionsStatus
    case listApplications(ListApplicationsRequest)
    case listWindows(ListWindowsRequest)
    /// WP7: capture one window, run OCR/redaction as required, and persist
    /// the result into the MCP artifact store. `capture_application`
    /// (`05-mcp-server-contract.md` section 3) is deliberately *not* a
    /// separate broker operation: the helper implements it by issuing one
    /// `listWindows` plus repeated `captureWindow` calls, reusing this
    /// operation and the existing discovery operation instead of adding a
    /// second, largely-duplicate multi-window code path at the broker layer.
    case captureWindow(CaptureWindowRequest)
    /// Returns the same immutable manifest available through the
    /// `berryshot://captures/{id}/manifest` resource.
    case getCaptureManifest(GetCaptureManifestRequest)
    /// Resolves an opaque capture ID + resource kind to a broker-issued,
    /// already-contained absolute path the helper may read directly
    /// (`05-mcp-server-contract.md` section 7). Used for all three resource
    /// kinds (image/manifest/ocr) and for the bounded inline preview, which
    /// the helper builds by downsizing the same on-disk final image.
    case resolveArtifactResource(ResolveArtifactResourceRequest)
    /// Best-effort cancellation of another in-flight or still-queued
    /// request, identified by its `requestID`. Always acknowledged; racing
    /// with a request that already finished is not an error.
    case cancel(UUID)

    // MARK: - WP8 documentation sessions and guarded AX automation
    // (`06-agent-documentation-security.md`)

    case documentationSessionBegin(DocumentationSessionBeginRequest)
    case documentationSessionStatus(DocumentationSessionStatusRequest)
    /// Captures one window through the exact same pipeline
    /// `captureWindow` uses, scoped by the session (bundle allowlist,
    /// locked-in redaction policy/style, artifact limit) rather than by
    /// caller-supplied redaction arguments.
    case documentationSessionCaptureStep(DocumentationSessionCaptureStepRequest)
    case documentationSessionEnd(DocumentationSessionEndRequest)
    /// Guarded interactive automation
    /// (`06-agent-documentation-security.md` section 4). Every one of these
    /// five operations validates `sessionID` first and only ever acts on
    /// that session's allowlisted bundle identifier.
    case launchApplication(LaunchApplicationRequest)
    case activateApplication(ActivateApplicationRequest)
    case inspectUI(InspectUIRequest)
    case performUIAction(PerformUIActionRequest)
    case waitForUI(WaitForUIRequest)
}

extension BrokerOperation: Codable {
    private enum Kind: String, Codable {
        case ping
        case permissionsStatus
        case listApplications
        case listWindows
        case captureWindow
        case getCaptureManifest
        case resolveArtifactResource
        case cancel
        case documentationSessionBegin
        case documentationSessionStatus
        case documentationSessionCaptureStep
        case documentationSessionEnd
        case launchApplication
        case activateApplication
        case inspectUI
        case performUIAction
        case waitForUI
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .ping:
            self = .ping
        case .permissionsStatus:
            self = .permissionsStatus
        case .listApplications:
            self = .listApplications(try container.decode(ListApplicationsRequest.self, forKey: .payload))
        case .listWindows:
            self = .listWindows(try container.decode(ListWindowsRequest.self, forKey: .payload))
        case .captureWindow:
            self = .captureWindow(try container.decode(CaptureWindowRequest.self, forKey: .payload))
        case .getCaptureManifest:
            self = .getCaptureManifest(try container.decode(GetCaptureManifestRequest.self, forKey: .payload))
        case .resolveArtifactResource:
            self = .resolveArtifactResource(try container.decode(ResolveArtifactResourceRequest.self, forKey: .payload))
        case .cancel:
            self = .cancel(try container.decode(UUID.self, forKey: .payload))
        case .documentationSessionBegin:
            self = .documentationSessionBegin(try container.decode(DocumentationSessionBeginRequest.self, forKey: .payload))
        case .documentationSessionStatus:
            self = .documentationSessionStatus(try container.decode(DocumentationSessionStatusRequest.self, forKey: .payload))
        case .documentationSessionCaptureStep:
            self = .documentationSessionCaptureStep(try container.decode(DocumentationSessionCaptureStepRequest.self, forKey: .payload))
        case .documentationSessionEnd:
            self = .documentationSessionEnd(try container.decode(DocumentationSessionEndRequest.self, forKey: .payload))
        case .launchApplication:
            self = .launchApplication(try container.decode(LaunchApplicationRequest.self, forKey: .payload))
        case .activateApplication:
            self = .activateApplication(try container.decode(ActivateApplicationRequest.self, forKey: .payload))
        case .inspectUI:
            self = .inspectUI(try container.decode(InspectUIRequest.self, forKey: .payload))
        case .performUIAction:
            self = .performUIAction(try container.decode(PerformUIActionRequest.self, forKey: .payload))
        case .waitForUI:
            self = .waitForUI(try container.decode(WaitForUIRequest.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ping:
            try container.encode(Kind.ping, forKey: .type)
        case .permissionsStatus:
            try container.encode(Kind.permissionsStatus, forKey: .type)
        case .listApplications(let payload):
            try container.encode(Kind.listApplications, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .listWindows(let payload):
            try container.encode(Kind.listWindows, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .captureWindow(let payload):
            try container.encode(Kind.captureWindow, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .getCaptureManifest(let payload):
            try container.encode(Kind.getCaptureManifest, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .resolveArtifactResource(let payload):
            try container.encode(Kind.resolveArtifactResource, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .cancel(let requestID):
            try container.encode(Kind.cancel, forKey: .type)
            try container.encode(requestID, forKey: .payload)
        case .documentationSessionBegin(let payload):
            try container.encode(Kind.documentationSessionBegin, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .documentationSessionStatus(let payload):
            try container.encode(Kind.documentationSessionStatus, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .documentationSessionCaptureStep(let payload):
            try container.encode(Kind.documentationSessionCaptureStep, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .documentationSessionEnd(let payload):
            try container.encode(Kind.documentationSessionEnd, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .launchApplication(let payload):
            try container.encode(Kind.launchApplication, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .activateApplication(let payload):
            try container.encode(Kind.activateApplication, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .inspectUI(let payload):
            try container.encode(Kind.inspectUI, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .performUIAction(let payload):
            try container.encode(Kind.performUIAction, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .waitForUI(let payload):
            try container.encode(Kind.waitForUI, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

/// Results mirroring ``BrokerOperation`` one-for-one. Same rationale for
/// hand-written `Codable` as above.
public enum BrokerResult: Sendable, Equatable {
    case pong
    case permissionsStatus(PermissionsStatusDTO)
    case applications(ListApplicationsResult)
    case windows(ListWindowsResult)
    /// Result of both `.captureWindow` and `.getCaptureManifest` — the same
    /// immutable manifest shape either way (`05-mcp-server-contract.md`
    /// section 3: "get_capture_manifest... Output is the same immutable
    /// sanitized manifest available through the manifest resource").
    case manifest(CaptureManifestDTO)
    case artifactResource(ArtifactResourceLocationDTO)
    case cancelAcknowledged
    /// Result of `documentationSessionBegin`/`Status`/`End`, and also of
    /// `documentationSessionCaptureStep` (the session's full state *after*
    /// recording the step, not just the new step in isolation).
    case documentationSession(DocumentationSessionDTO)
    case applicationLaunch(ApplicationLaunchResultDTO)
    case uiSnapshot(UISnapshotDTO)
    case uiActionResult(UIActionResultDTO)
    case uiWaitResult(UIWaitResultDTO)
}

extension BrokerResult: Codable {
    private enum Kind: String, Codable {
        case pong
        case permissionsStatus
        case applications
        case windows
        case manifest
        case artifactResource
        case cancelAcknowledged
        case documentationSession
        case applicationLaunch
        case uiSnapshot
        case uiActionResult
        case uiWaitResult
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .pong:
            self = .pong
        case .permissionsStatus:
            self = .permissionsStatus(try container.decode(PermissionsStatusDTO.self, forKey: .payload))
        case .applications:
            self = .applications(try container.decode(ListApplicationsResult.self, forKey: .payload))
        case .windows:
            self = .windows(try container.decode(ListWindowsResult.self, forKey: .payload))
        case .manifest:
            self = .manifest(try container.decode(CaptureManifestDTO.self, forKey: .payload))
        case .artifactResource:
            self = .artifactResource(try container.decode(ArtifactResourceLocationDTO.self, forKey: .payload))
        case .cancelAcknowledged:
            self = .cancelAcknowledged
        case .documentationSession:
            self = .documentationSession(try container.decode(DocumentationSessionDTO.self, forKey: .payload))
        case .applicationLaunch:
            self = .applicationLaunch(try container.decode(ApplicationLaunchResultDTO.self, forKey: .payload))
        case .uiSnapshot:
            self = .uiSnapshot(try container.decode(UISnapshotDTO.self, forKey: .payload))
        case .uiActionResult:
            self = .uiActionResult(try container.decode(UIActionResultDTO.self, forKey: .payload))
        case .uiWaitResult:
            self = .uiWaitResult(try container.decode(UIWaitResultDTO.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pong:
            try container.encode(Kind.pong, forKey: .type)
        case .permissionsStatus(let payload):
            try container.encode(Kind.permissionsStatus, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .applications(let payload):
            try container.encode(Kind.applications, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .windows(let payload):
            try container.encode(Kind.windows, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .manifest(let payload):
            try container.encode(Kind.manifest, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .artifactResource(let payload):
            try container.encode(Kind.artifactResource, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .cancelAcknowledged:
            try container.encode(Kind.cancelAcknowledged, forKey: .type)
        case .documentationSession(let payload):
            try container.encode(Kind.documentationSession, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .applicationLaunch(let payload):
            try container.encode(Kind.applicationLaunch, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .uiSnapshot(let payload):
            try container.encode(Kind.uiSnapshot, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .uiActionResult(let payload):
            try container.encode(Kind.uiActionResult, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .uiWaitResult(let payload):
            try container.encode(Kind.uiWaitResult, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}
