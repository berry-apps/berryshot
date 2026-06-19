# Live Meeting Notes & Microphone Fix Implementation Plan

## Goal Description
Build a robust real-time meeting transcription and summarization feature ("Live Meeting Notes") and resolve the microphone background noise / mute issues for screen recording.

---

## Prerequisites & Key Design Decisions

### Speaker Attribution Model
Tag mỗi segment bằng nguồn audio:
- `.mic` — giọng người dùng (từ AVCaptureSession)
- `.systemAudio` — giọng người kia qua speaker/headphone (từ SCStream)

```swift
struct TranscriptSegment {
    enum Source { case mic, systemAudio }
    let source: Source
    let text: String
    let timestamp: TimeInterval  // tính từ lúc bắt đầu recording
}
```

Đặt `TranscriptSegment` vào `Sources/Core/Models.swift` cùng với các model hiện có.

### Speech Recognition: On-Device (Bắt buộc)
App target macOS 14+ → dùng Apple's on-device model, **không gửi audio lên server**:
```swift
request.requiresOnDeviceRecognition = true
```
Kiểm tra trước: `SFSpeechRecognizer.shared?.supportsOnDeviceRecognition == true`.  
Nếu thiết bị không hỗ trợ (Intel Mac cũ), fallback về online với cảnh báo privacy trong UI.

### SFSpeech Request Lifecycle
Apple giới hạn mỗi `SFSpeechAudioBufferRecognitionRequest` khoảng **60 giây**. Cần tự restart định kỳ:
- Dùng timer 45 giây để restart request trước khi hit limit
- Nối transcript từ request cũ + mới liền mạch (append, không replace)

---

## Proposed Changes

### Step 1 — Core Models
#### [MODIFY] `Sources/Core/Models.swift`
- Thêm `TranscriptSegment` struct (xem định nghĩa ở trên).

---

### Step 2 — Audio Conversion Helper
#### [NEW] `Sources/Recording/AudioBufferConverter.swift`
SFSpeech yêu cầu `AVAudioPCMBuffer` ở format 16kHz mono. Pipeline hiện tại capture ở 48kHz stereo — cần convert.

```swift
import AVFoundation

enum AudioBufferConverter {
    // Output format SFSpeech chấp nhận tốt nhất
    static let speechFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// Convert CMSampleBuffer từ AVCapture/SCStream → AVAudioPCMBuffer 16kHz mono
    static func convert(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }

        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)!.pointee
        guard let inputFormat = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else { return nil }
        inputBuffer.frameLength = frameCount

        // Copy raw audio data vào PCM buffer
        var blockBufferLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                    totalLengthOut: &blockBufferLength, dataPointerOut: &dataPointer)
        if let src = dataPointer, let dst = inputBuffer.int16ChannelData {
            memcpy(dst[0], src, blockBufferLength)
        }

        // Resample xuống 16kHz mono
        guard let converter = AVAudioConverter(from: inputFormat, to: speechFormat) else { return nil }
        let ratio = speechFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(frameCount) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: speechFormat, frameCapacity: outputCapacity) else { return nil }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return inputBuffer
        }
        return error == nil ? outputBuffer : nil
    }
}
```

---

### Step 3 — Live Transcription Service
#### [NEW] `Sources/AI/LiveTranscriptionService.swift`

Hai recognizer chạy song song (mic + system audio), mỗi cái tự restart sau 45 giây.

```swift
import Speech
import AVFoundation

@MainActor
class LiveTranscriptionService: ObservableObject {
    static let shared = LiveTranscriptionService()

    @Published var liveTranscript: [TranscriptSegment] = []

    private var micRecognizer: SFSpeechRecognizer?
    private var systemRecognizer: SFSpeechRecognizer?
    private var micRequest: SFSpeechAudioBufferRecognitionRequest?
    private var systemRequest: SFSpeechAudioBufferRecognitionRequest?
    private var micTask: SFSpeechRecognitionTask?
    private var systemTask: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var recordingStartTime: Date = Date()

    func start() {
        recordingStartTime = Date()
        liveTranscript = []
        setupRecognizers()
        scheduleRestart()
    }

    func stop() {
        restartTimer?.invalidate()
        micTask?.finish()
        systemTask?.finish()
        micRequest = nil
        systemRequest = nil
    }

    func append(sampleBuffer: CMSampleBuffer, from source: TranscriptSegment.Source) {
        guard let pcm = AudioBufferConverter.convert(sampleBuffer) else { return }
        switch source {
        case .mic:    micRequest?.append(pcm)
        case .systemAudio: systemRequest?.append(pcm)
        }
    }

    // MARK: - Private

    private func setupRecognizers() {
        let locale = Locale(identifier: "vi-VN") // hoặc để user chọn trong Settings
        micRecognizer = SFSpeechRecognizer(locale: locale)
        systemRecognizer = SFSpeechRecognizer(locale: locale)

        startMicRecognition()
        startSystemRecognition()
    }

    private func startMicRecognition() {
        micTask?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true  // macOS 14+, privacy-safe
        req.shouldReportPartialResults = true
        self.micRequest = req

        micTask = micRecognizer?.recognitionTask(with: req) { [weak self] result, _ in
            guard let self, let result else { return }
            if result.isFinal {
                let ts = TranscriptSegment(
                    source: .mic,
                    text: result.bestTranscription.formattedString,
                    timestamp: Date().timeIntervalSince(self.recordingStartTime)
                )
                Task { @MainActor in self.liveTranscript.append(ts) }
            }
        }
    }

    private func startSystemRecognition() {
        systemTask?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        self.systemRequest = req

        systemTask = systemRecognizer?.recognitionTask(with: req) { [weak self] result, _ in
            guard let self, let result else { return }
            if result.isFinal {
                let ts = TranscriptSegment(
                    source: .systemAudio,
                    text: result.bestTranscription.formattedString,
                    timestamp: Date().timeIntervalSince(self.recordingStartTime)
                )
                Task { @MainActor in self.liveTranscript.append(ts) }
            }
        }
    }

    private func scheduleRestart() {
        restartTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.startMicRecognition()
                self?.startSystemRecognition()
            }
        }
    }
}
```

---

### Step 4 — Core Capture & Audio

#### [MODIFY] `Sources/Core/Models.swift`
- Thêm `TranscriptSegment` (xem Step 1).

#### [MODIFY] `Sources/Recording/RecordingManager.swift`
- Thêm `@Published var isMicMuted: Bool = false`
- Thêm `func toggleMicMute()`
- Gọi `LiveTranscriptionService.shared.start()` trong `startRecording()`
- Gọi `LiveTranscriptionService.shared.stop()` trong `stopRecording()`

#### [MODIFY] `Sources/Recording/ScreenRecordingService.swift`

**Mic mute** — trong `captureOutput(_:didOutput:from:)`:
```swift
public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    if RecordingManager.shared.isMicMuted {
        // Append silent buffer để tránh A/V desync
        writer?.appendMicAudio(sampleBuffer: makeSilentBuffer(like: sampleBuffer))
    } else {
        writer?.appendMicAudio(sampleBuffer: sampleBuffer)
        // Forward sang transcription (copy riêng, không dùng chung reference)
        if let copy = CMSampleBuffer.copy(sampleBuffer) {
            LiveTranscriptionService.shared.append(sampleBuffer: copy, from: .mic)
        }
    }
}
```

**System audio forward** — trong `stream(_:didOutputSampleBuffer:of:)`:
```swift
case .audio:
    writer?.appendAudio(sampleBuffer: sampleBuffer)
    if let copy = CMSampleBuffer.copy(sampleBuffer) {
        LiveTranscriptionService.shared.append(sampleBuffer: copy, from: .systemAudio)
    }
```

> **Lưu ý**: Dùng `CMSampleBufferCreateCopy` (wrap thành extension `CMSampleBuffer.copy()`) để tránh 2 consumer cùng consume 1 buffer.

---

### Step 5 — AI Meeting Minutes

#### [MODIFY] `Sources/AI/Phase3Workflow.swift`
```swift
public func generateMeetingMinutes(transcript: [TranscriptSegment]) async throws -> String {
    let formatted = transcript
        .sorted { $0.timestamp < $1.timestamp }
        .map { seg in
            let speaker = seg.source == .mic ? "Bạn" : "Người kia"
            let time = formatTime(seg.timestamp)
            return "[\(time)] \(speaker): \(seg.text)"
        }
        .joined(separator: "\n")

    let prompt = """
    Bạn là trợ lý tạo biên bản cuộc họp chuyên nghiệp. Dựa trên transcript sau, \
    hãy tạo biên bản cuộc họp theo định dạng Markdown gồm: \
    Tóm tắt, Các điểm thảo luận chính, Quyết định đã đưa ra, Việc cần làm (Action Items).

    Transcript:
    \(formatted)
    """
    return try await provider.generateText(prompt: prompt, image: nil)
}

private func formatTime(_ seconds: TimeInterval) -> String {
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return String(format: "%02d:%02d", m, s)
}
```

---

### Step 6 — User Interface

#### [MODIFY] `Sources/Capture/ToolbarView.swift`
- Thêm nút **"Mute Mic"**: icon `mic.slash.fill`, màu đỏ khi muted, trắng khi không.
- Thêm nút **"Live Notes"**: icon `doc.text.fill`, toggle show/hide `LiveMeetingWindowController`.
- Bind cả hai với `RecordingManager.shared`.

#### [NEW] `Sources/AI/LiveMeetingWindowController.swift`
Pattern giống `AIResultWindowController` (borderless, clear background, `.screenSaver + 2` level):
- `ScrollView` hiển thị `liveTranscript` realtime, tự scroll xuống cuối.
- Mỗi segment hiển thị: icon nguồn (mic/speaker) + timestamp + text.
- Nút **"Tạo Biên Bản"** ở bottom → gọi `Phase3Workflow.generateMeetingMinutes()` → show result trong `AIResultWindowController`.
- Indicator nhỏ (chấm xanh nhấp nháy) khi đang nhận audio.

---

## Implementation Order

```
1. TranscriptSegment model        → verify: build passes
2. AudioBufferConverter           → verify: unit test convert() trả về non-nil với 48kHz stereo buffer
3. LiveTranscriptionService       → verify: log segment khi nói vào mic
4. RecordingManager mute + start/stop service → verify: UI phản ánh đúng
5. ScreenRecordingService forward buffers → verify: cả 2 stream có transcript
6. Phase3Workflow.generateMeetingMinutes → verify: output có đủ 4 sections
7. ToolbarView UI                 → verify: mute button đổi màu, notes window open/close
8. LiveMeetingWindowController    → verify: scroll realtime, generate button hoạt động
```

---

## Risk & Mitigation

| Risk | Giải pháp |
|------|-----------|
| Intel Mac không có on-device model | Kiểm tra `supportsOnDeviceRecognition`, fallback online + cảnh báo trong UI |
| System audio transcript lẫn nhiều noise (nhạc, notif) | Có thể thêm option "Chỉ mic" trong Settings, hoặc filter segment quá ngắn (<3 từ) |
| Locale nhận sai tiếng | Cho user chọn locale trong AI Settings (vi-VN, en-US) |
| `AVAudioConverter` crash với format không chuẩn | Kiểm tra `inputFormat != nil` trước khi convert, return nil nếu fail |
