import Foundation
import CoreGraphics
import ScreenCaptureKit
import AVFoundation
import Speech

@MainActor
public class RecordingManager: ObservableObject {
    public static let shared = RecordingManager()
    
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isMicMuted: Bool = false
    
    private var screenRecordingService = ScreenRecordingService()
    private var annotationService = AnnotationRecordingService()
    
    private var timer: Timer?
    private var startTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartDate: Date?
    private var currentVideoURL: URL?
    
    private init() {}
    
    public func startRecording(region rect: CGRect, displayID: CGDirectDisplayID, excludingWindowIDs: [CGWindowID]) async throws {
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

        // Start screen recording (starts AVCaptureSession for mic + SCStream for system audio)
        currentVideoURL = try await screenRecordingService.startRecording(region: rect, displayID: displayID, excludingWindowIDs: excludingWindowIDs)

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
                if self.isPaused {
                    // Show duration up to pause point
                    self.recordingDuration = Date().timeIntervalSince(start) - self.pausedDuration - (self.pauseStartDate.map { Date().timeIntervalSince($0) } ?? 0)
                } else {
                    self.recordingDuration = Date().timeIntervalSince(start) - self.pausedDuration
                }
            }
        }
    }
    
    public func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pauseStartDate = Date()
        screenRecordingService.pause()
    }
    
    public func updateRegion(rect: CGRect) async {
        guard isRecording else { return }
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
