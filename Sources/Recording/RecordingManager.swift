import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit
import AVFoundation
import Speech

@MainActor
public class RecordingManager: ObservableObject {
    public static let shared = RecordingManager()
    
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isMicMuted: Bool = false
    /// One-shot signal: flips true when a window-sourced recording session's
    /// target window disappears mid-recording (closed, app quit). This
    /// manager only detects and reports it — it never stops recording on its
    /// own — so there remains exactly one code path (`stopRecording()`,
    /// driven by whoever started the session) that ever finalizes a
    /// recording.
    @Published public var windowRecordingDidDisappear = false

    private var screenRecordingService = ScreenRecordingService()
    private var annotationService = AnnotationRecordingService()

    private var timer: Timer?
    private var startTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartDate: Date?
    private var currentVideoURL: URL?
    /// Set only for a window-sourced session (`startRecording(windowDescriptor:)`);
    /// nil for a region-sourced one. Lets the existing 1s duration timer also
    /// double as a liveness check with no second timer. The owner PID is
    /// checked alongside the ID because `CGWindowID`s can be reused by the
    /// window server after their original window closes — an ID-only check
    /// could otherwise treat some unrelated new window as proof the original
    /// one is still alive.
    private var recordingWindow: (id: CGWindowID, ownerPID: Int32)?
    /// `isRecording` only flips true after several `await`s below (mic
    /// permission, then the actual stream/writer setup) — a `guard
    /// !isRecording` alone is not atomic across that gap, so two starts
    /// racing could both pass it and clobber `ScreenRecordingService`'s
    /// shared stream/writer state. This is set synchronously, before the
    /// first `await`, so a second call arriving anywhere in that gap sees it
    /// immediately (MainActor isolation serializes the two entries' checks).
    private var isStartingRecording = false

    private init() {}

    public func startRecording(region rect: CGRect, displayID: CGDirectDisplayID, excludingWindowIDs: [CGWindowID]) async throws {
        try await beginRecordingSession(window: nil) {
            try await self.screenRecordingService.startRecording(region: rect, displayID: displayID, excludingWindowIDs: excludingWindowIDs)
        }
    }

    /// Records a single application window instead of a screen region. Only
    /// a `WindowDescriptor` is retained by the caller; the live `SCWindow` is
    /// resolved for the duration of this call only, matching how
    /// `WindowCaptureService` is used for screenshot capture elsewhere.
    public func startRecording(windowDescriptor: WindowDescriptor) async throws {
        try await beginRecordingSession(window: (id: windowDescriptor.id, ownerPID: windowDescriptor.processID)) {
            try await WindowCaptureService.shared.withResolvedWindow(windowDescriptor) { window in
                try await self.screenRecordingService.startRecording(window: window)
            }
        }
    }

    private func beginRecordingSession(window: (id: CGWindowID, ownerPID: Int32)?, startCapture: () async throws -> URL) async throws {
        // `RecordingManager` is a process-wide singleton representing the one
        // active recording session; without this, two starts racing (e.g.
        // two overlay sessions both mid-`startRecording`) would clobber each
        // other's `stream`/`writer`/`timer`, orphaning the first one's
        // AVAssetWriter mid-write (never finalized -> corrupt file) and
        // leaking its mic session.
        guard !isRecording, !isStartingRecording else {
            throw NSError(domain: "RecordingManager", code: 409, userInfo: [NSLocalizedDescriptionKey: "A recording is already in progress."])
        }
        isStartingRecording = true
        defer { isStartingRecording = false }

        if !CGPreflightScreenCaptureAccess() {
            throw NSError(domain: "RecordingManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission denied. Please enable it in System Settings -> Privacy & Security -> Screen Recording, and restart the app."])
        }

        // Request microphone permission (overlay window is already lowered by OverlayViewModel)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            let granted: Bool = await withCheckedContinuation { continuation in
                if #available(macOS 14.0, *) {
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                } else {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
            guard granted else {
                throw NSError(domain: "RecordingManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Microphone access not granted."])
            }
        } else if micStatus != .authorized {
            throw NSError(domain: "RecordingManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Microphone access not granted. Please allow it in System Settings → Privacy & Security → Microphone."])
        }

        // Start live transcription FIRST so AVAudioEngine can claim the mic
        // before AVCaptureSession starts. On macOS both can coexist but first-claimant wins.
        LiveTranscriptionService.shared.start()

        windowRecordingDidDisappear = false

        // Start screen recording (starts AVCaptureSession for mic + SCStream for system audio).
        // A window-sourced session can fail here specifically because the
        // target window disappeared between selection and this call
        // (`WindowCaptureService.withResolvedWindow` throws) — a first-class,
        // common failure mode for this path, unlike the region path's rarer
        // failure causes. Stop transcription before rethrowing so a failed
        // start never leaves it claiming the mic with nothing recording.
        do {
            currentVideoURL = try await startCapture()
        } catch {
            LiveTranscriptionService.shared.stop()
            throw error
        }

        // Only set once every throwing step above has succeeded, so a failed
        // start never leaves stale window-liveness state behind.
        recordingWindow = window

        // Start annotation tracking
        annotationService.startRecording()

        isRecording = true
        startTime = Date()
        pausedDuration = 0
        pauseStartDate = nil
        recordingDuration = 0

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.startTime else { return }

                if let window = self.recordingWindow, !Self.isWindowStillOnScreen(window.id, ownedBy: window.ownerPID) {
                    // Stop the polling only — the actual stop/finalize/save
                    // is left entirely to whoever started this session,
                    // reached via the `windowRecordingDidDisappear` signal.
                    self.recordingWindow = nil
                    self.windowRecordingDidDisappear = true
                    return
                }

                if self.isPaused {
                    // Show duration up to pause point
                    self.recordingDuration = Date().timeIntervalSince(start) - self.pausedDuration - (self.pauseStartDate.map { Date().timeIntervalSince($0) } ?? 0)
                } else {
                    self.recordingDuration = Date().timeIntervalSince(start) - self.pausedDuration
                }
            }
        }
    }

    /// Cheap existence check for exactly one window. Deliberately not
    /// `SCShareableContent.current` (async, permission-gated, and enumerates
    /// every window of every running app) — this runs once a second for the
    /// life of every window-sourced recording, so it needs to stay as close
    /// to free as possible. Also checks the owning process, since the window
    /// server can reuse a `CGWindowID` for an unrelated new window shortly
    /// after the original one closes — an ID-only check could otherwise
    /// treat that unrelated window as proof the original is still alive.
    private static func isWindowStillOnScreen(_ windowID: CGWindowID, ownedBy ownerPID: Int32) -> Bool {
        guard let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let entry = info.first,
              let entryPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else {
            return false
        }
        return entryPID == ownerPID
    }
    
    public func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pauseStartDate = Date()
        screenRecordingService.pause()
    }
    
    /// A window-sourced session's `SCContentFilter` was built with
    /// `desktopIndependentWindow:`, whose coordinate space is the window's
    /// own bounds — not the screen-relative overlay coordinates `rect` here
    /// is expressed in. Applying it as `sourceRect` would crop against a
    /// region that doesn't correspond to any part of the window, corrupting
    /// the rest of the recording. There is nothing meaningful to "update" for
    /// that session anyway — the filter already tracks the window itself —
    /// so this silently no-ops for a window-sourced session instead.
    public func updateRegion(rect: CGRect) async {
        guard isRecording, recordingWindow == nil else { return }
        do {
            try await screenRecordingService.updateRegion(rect: rect)
        } catch {
            print("Failed to update recording region: \(error)")
        }
    }
    
    public func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        if let pauseStart = pauseStartDate {
            pausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartDate = nil
        }
        screenRecordingService.resume()
    }
    
    public func toggleMicMute() {
        isMicMuted.toggle()
        screenRecordingService.isMicMuted = isMicMuted
        LiveTranscriptionService.shared.isMicMuted = isMicMuted
    }

    public func stopRecording() async throws -> (videoURL: URL, annotationsURL: URL?) {
        timer?.invalidate()
        timer = nil
        recordingWindow = nil
        isRecording = false
        isMicMuted = false
        screenRecordingService.isMicMuted = false
        LiveTranscriptionService.shared.stop()
        
        // Stop screen recording
        guard let videoURL = try await screenRecordingService.stopRecording() else {
            throw NSError(domain: "RecordingManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get video URL"])
        }
        
        // Stop annotation tracking
        _ = annotationService.stopRecording()
        
        let tempDir = FileManager.default.temporaryDirectory
        let jsonURL = tempDir.appendingPathComponent("Annotations-\(UUID().uuidString).json")
        try annotationService.exportJSON(to: jsonURL)
        
        return (videoURL, jsonURL)
    }
    
    public func recordAnnotationEvent(type: AnnotationEventType, elementData: Data? = nil) {
        annotationService.recordEvent(type: type, elementData: elementData)
    }
}
