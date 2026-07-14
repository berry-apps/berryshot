import Foundation
import AVFoundation
import CoreMedia

public enum RecordingError: Error {
    case invalidOutputURL
    case writerCreationFailed(Error)
    case inputAdditionFailed
    case startWritingFailed
}

public class RecordingWriter: @unchecked Sendable {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    
    private var isWriting = false
    private var isPaused = false
    private var hasStartedSession = false
    
    private var timeOffset: CMTime = .zero
    private var pauseStartTime: CMTime?
    private var firstRawPTS: CMTime?
    
    public init() {}
    
    public func startRecording(
        to url: URL,
        videoSettings: [String: Any],
        audioSettings: [String: Any]?,
        micSettings: [String: Any]? = nil
    ) throws {
        do {
            assetWriter = try AVAssetWriter(url: url, fileType: .mov)
        } catch {
            throw RecordingError.writerCreationFailed(error)
        }
        
        guard let assetWriter = assetWriter else { throw RecordingError.invalidOutputURL }
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        if assetWriter.canAdd(videoInput!) {
            assetWriter.add(videoInput!)
        } else {
            throw RecordingError.inputAdditionFailed
        }
        
        if let audioSettings = audioSettings {
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(audioInput!) {
                assetWriter.add(audioInput!)
            }
        }
        
        if let micSettings = micSettings {
            micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            micInput?.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(micInput!) {
                assetWriter.add(micInput!)
            }
        }
        
        // Reset state for new session
        hasStartedSession = false
        firstRawPTS = nil
        timeOffset = .zero
        pauseStartTime = nil
        
        if !assetWriter.startWriting() {
            throw RecordingError.startWritingFailed
        }
        isWriting = true
    }
    
    public func pause() {
        guard isWriting, !isPaused else { return }
        isPaused = true
    }
    
    public func resume() {
        guard isWriting, isPaused else { return }
        isPaused = false
        if pauseStartTime != nil {
            // We will calculate the offset on the next frame to get exact duration
        }
    }
    
    private func adjustPTS(for sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        let rawPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if isPaused {
            if pauseStartTime == nil {
                pauseStartTime = rawPTS
            }
            return nil
        }
        
        if let pauseStart = pauseStartTime {
            let pauseDuration = CMTimeSubtract(rawPTS, pauseStart)
            timeOffset = CMTimeAdd(timeOffset, pauseDuration)
            pauseStartTime = nil
        }
        
        if firstRawPTS == nil {
            firstRawPTS = rawPTS
        }
        
        let elapsed = CMTimeSubtract(rawPTS, firstRawPTS!)
        let adjustedPTS = CMTimeSubtract(elapsed, timeOffset)
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: adjustedPTS,
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        )
        
        if timingInfo.decodeTimeStamp != .invalid {
            let decodeElapsed = CMTimeSubtract(CMSampleBufferGetDecodeTimeStamp(sampleBuffer), firstRawPTS!)
            timingInfo.decodeTimeStamp = CMTimeSubtract(decodeElapsed, timeOffset)
        }
        
        var adjustedBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                              sampleBuffer: sampleBuffer,
                                              sampleTimingEntryCount: 1,
                                              sampleTimingArray: &timingInfo,
                                              sampleBufferOut: &adjustedBuffer)
        return adjustedBuffer
    }
    
    public func appendVideo(sampleBuffer: CMSampleBuffer) {
        guard isWriting, let videoInput = videoInput, videoInput.isReadyForMoreMediaData else { return }
        guard let adjustedBuffer = adjustPTS(for: sampleBuffer) else { return }
        
        if !hasStartedSession {
            assetWriter?.startSession(atSourceTime: .zero)
            hasStartedSession = true
        }
        
        videoInput.append(adjustedBuffer)
    }
    
    public func appendAudio(sampleBuffer: CMSampleBuffer) {
        guard isWriting, let audioInput = audioInput, audioInput.isReadyForMoreMediaData else { return }
        guard let adjustedBuffer = adjustPTS(for: sampleBuffer) else { return }
        
        if !hasStartedSession {
            assetWriter?.startSession(atSourceTime: .zero)
            hasStartedSession = true
        }
        
        audioInput.append(adjustedBuffer)
    }
    
    public func appendMicAudio(sampleBuffer: CMSampleBuffer) {
        guard isWriting, let micInput = micInput, micInput.isReadyForMoreMediaData else { return }
        guard let adjustedBuffer = adjustPTS(for: sampleBuffer) else { return }
        
        if !hasStartedSession {
            assetWriter?.startSession(atSourceTime: .zero)
            hasStartedSession = true
        }
        
        micInput.append(adjustedBuffer)
    }
    
    public func finishRecording() async throws {
        isWriting = false
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()
        
        if !hasStartedSession {
            assetWriter?.cancelWriting()
            throw NSError(domain: "RecordingWriter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recording stopped before any frames were captured. (Recording was too short or no screen content updated)."])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            assetWriter?.finishWriting { [weak self] in
                guard let self = self, let writer = self.assetWriter else {
                    continuation.resume(throwing: RecordingError.startWritingFailed)
                    return
                }
                if writer.status == .failed, let error = writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
