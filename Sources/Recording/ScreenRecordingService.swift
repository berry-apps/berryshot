import Foundation
import ScreenCaptureKit
import AVFoundation
import VideoToolbox
import AppKit

public class ScreenRecordingService: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var writer: RecordingWriter?
    private var outputURL: URL?
    private var currentConfig: SCStreamConfiguration?
    private var micSession: AVCaptureSession?
    // Written from main thread, read from audio capture queues — single Bool is safe
    var isMicMuted: Bool = false
    
    public override init() {
        super.init()
    }
    
    public func startRecording(region rect: CGRect, displayID: CGDirectDisplayID, excludingWindowIDs: [CGWindowID]) async throws -> URL {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw NSError(domain: "ScreenRecordingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        
        let excludedWindows = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let actualFilter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        
        // Find the actual screen being recorded to get its backing scale factor
        var scale: CGFloat = 2.0
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenNumber == displayID {
                scale = screen.backingScaleFactor
                break
            }
        }
        
        let targetWidth = Int(rect.width * scale)
        let targetHeight = Int(rect.height * scale)
        // HEVC encoder requires dimensions to be a multiple of 2
        configuration.width = targetWidth % 2 == 0 ? targetWidth : targetWidth + 1
        configuration.height = targetHeight % 2 == 0 ? targetHeight : targetHeight + 1
        configuration.showsCursor = true
        configuration.capturesAudio = true // System audio
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        
        // Output URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "Recording-\(UUID().uuidString).mov"
        let fileURL = tempDir.appendingPathComponent(fileName)
        self.outputURL = fileURL
        
        writer = RecordingWriter()
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 50_000_000, // 50 Mbps for crisp high-res recording
                AVVideoExpectedSourceFrameRateKey: 60
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ]
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        
        
        let micSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]
        
        currentConfig = configuration
        try writer?.startRecording(to: fileURL, videoSettings: videoSettings, audioSettings: audioSettings, micSettings: micSettings)
        
        stream = SCStream(filter: actualFilter, configuration: configuration, delegate: self)
        let queue = DispatchQueue(label: "com.berryshot.recording")
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        
        // Initialize microphone recording using AVCaptureSession (works on macOS 14+)
        let session = AVCaptureSession()
        
        guard let micDevice = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "ScreenRecordingService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No microphone device found"])
        }
        
        let micInput = try AVCaptureDeviceInput(device: micDevice)
        if session.canAddInput(micInput) {
            session.addInput(micInput)
        } else {
            throw NSError(domain: "ScreenRecordingService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot add microphone input to session"])
        }
        
        let audioOutput = AVCaptureAudioDataOutput()
        let micQueue = DispatchQueue(label: "com.berryshot.mic")
        audioOutput.setSampleBufferDelegate(self, queue: micQueue)
        
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        } else {
            throw NSError(domain: "ScreenRecordingService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot add microphone output to session"])
        }
        
        self.micSession = session
        Task.detached {
            session.startRunning()
        }
        
        try await stream?.startCapture()
        
        return fileURL
    }
    
    public func stopRecording() async throws -> URL? {
        micSession?.stopRunning()
        micSession = nil
        
        try await stream?.stopCapture()
        try await writer?.finishRecording()
        return outputURL
    }
    
    public func updateRegion(rect: CGRect) async throws {
        guard let stream = stream, let config = currentConfig else { return }
        
        // We cannot change the width/height of the configuration because AVAssetWriter 
        // expects fixed dimensions. We only update the sourceRect.
        // ScreenCaptureKit will automatically scale/crop the new sourceRect into the fixed video dimensions.
        config.sourceRect = rect
        
        try await stream.updateConfiguration(config)
    }
    
    public func pause() {
        writer?.pause()
    }
    
    public func resume() {
        writer?.resume()
    }
    
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            // Check if the sample buffer actually contains an image frame
            guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            
            // Append the video frame
            writer?.appendVideo(sampleBuffer: sampleBuffer)
        case .audio:
            writer?.appendAudio(sampleBuffer: sampleBuffer)
            LiveTranscriptionService.shared.append(sampleBuffer, from: .systemAudio)
        case .microphone:
            break
        @unknown default:
            break
        }
    }
    
    // AVCaptureAudioDataOutputSampleBufferDelegate implementation for microphone
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isMicMuted else { return }
        writer?.appendMicAudio(sampleBuffer: sampleBuffer)
        // Fallback: if AVAudioEngine failed to start, feed mic via AVCapture buffers instead
        LiveTranscriptionService.shared.append(sampleBuffer, from: .mic)
    }
}
