import Foundation
import CoreGraphics
import ScreenCaptureKit
import AVFoundation

@MainActor
public class RecordingManager: ObservableObject {
    public static let shared = RecordingManager()
    
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingDuration: TimeInterval = 0
    
    private var screenRecordingService = ScreenRecordingService()
    private var annotationService = AnnotationRecordingService()
    
    private var timer: Timer?
    private var startTime: Date?
    private var currentVideoURL: URL?
    
    private init() {}
    
    public func startRecording(region rect: CGRect, displayID: CGDirectDisplayID, excludingWindowIDs: [CGWindowID]) async throws {
        if !CGPreflightScreenCaptureAccess() {
            throw NSError(domain: "RecordingManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission denied. Please enable it in System Settings -> Privacy & Security -> Screen Recording, and restart the app."])
        }
        
        // Request microphone access if not determined
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        } else if micStatus == .denied || micStatus == .restricted {
            throw NSError(domain: "RecordingManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied. Please enable it in System Settings -> Privacy & Security -> Microphone, and restart the app."])
        }
        
        // Start screen recording
        currentVideoURL = try await screenRecordingService.startRecording(region: rect, displayID: displayID, excludingWindowIDs: excludingWindowIDs)
        
        // Start annotation tracking
        annotationService.startRecording()
        
        isRecording = true
        startTime = Date()
        recordingDuration = 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.startTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }
    
    public func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
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
        screenRecordingService.resume()
    }
    
    public func stopRecording() async throws -> (videoURL: URL, annotationsURL: URL?) {
        timer?.invalidate()
        timer = nil
        isRecording = false
        
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
