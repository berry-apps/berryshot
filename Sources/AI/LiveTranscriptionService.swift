import Speech
import AVFoundation

final class LiveTranscriptionService: ObservableObject, @unchecked Sendable {
    static let shared = LiveTranscriptionService()

    @Published var liveTranscript: [TranscriptSegment] = []
    @Published var partialMicText: String = ""
    @Published var partialSystemText: String = ""
    @Published var statusMessage: String = ""
    
    var isMicMuted: Bool = false

    private var startTime: Date = Date()
    private var isActive = false

    // Realtime provider (Deepgram / OpenAI Realtime)
    private var activeProvider: RealtimeTranscriptionProvider?

    // SFSpeech fallback (when no realtime provider configured)
    private var micRecognizer: SFSpeechRecognizer?
    private var systemRecognizer: SFSpeechRecognizer?
    private var micTask: SFSpeechRecognitionTask?
    private var systemTask: SFSpeechRecognitionTask?
    private var restartTimer: Timer?

    private var audioEngine: AVAudioEngine?
    private var usingRealtimeProvider = false

    private let lock = NSLock()
    private var _micRequest: SFSpeechAudioBufferRecognitionRequest?
    private var _systemRequest: SFSpeechAudioBufferRecognitionRequest?
    private var deviceObserver: NSObjectProtocol?

    private var micRequest: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { _micRequest } }
        set { lock.withLock { _micRequest = newValue } }
    }
    private var systemRequest: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { _systemRequest } }
        set { lock.withLock { _systemRequest = newValue } }
    }

    private init() {}

    // MARK: - Public API

    func start() {
        isActive = true
        usingRealtimeProvider = false
        startTime = Date()
        liveTranscript = []
        partialMicText = ""
        partialSystemText = ""
        statusMessage = "Starting..."

        // Permission is already granted by RecordingManager before this is called
        startAfterPermission()
    }

    private func startAfterPermission() {
        // Monitor audio device changes (headphone plug/unplug)
        deviceObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.isActive else { return }
                self.restartAudioEngine()
            }
        }

        if let settings = TranscriptionSettings.load() {
            // Use realtime provider (Deepgram or OpenAI Realtime)
            let provider = settings.makeProvider()
            let t0 = startTime
            provider.onStatus = { [weak self] msg in
                let s = self; DispatchQueue.main.async { s?.statusMessage = msg }
            }
            provider.onPartial = { [weak self] text in
                let s = self; DispatchQueue.main.async { s?.partialMicText = text }
            }
            provider.onFinal = { [weak self] text in
                guard let self else { return }
                let now = Date().timeIntervalSince(t0)
                DispatchQueue.main.async {
                    // Merge with previous segment if same source and recent (< 3s) and short text
                    if var last = self.liveTranscript.last,
                       last.source == .mic,
                       now - last.timestamp < 3.0,
                       last.text.count < 60 {
                        last.text += " " + text
                        self.liveTranscript[self.liveTranscript.count - 1] = last
                    } else {
                        let seg = TranscriptSegment(source: .mic, text: text, timestamp: now)
                        self.liveTranscript.append(seg)
                    }
                    self.partialMicText = ""
                }
            }
            activeProvider = provider
            usingRealtimeProvider = true
            startAudioEngine()
        } else {
            // Fallback: SFSpeechRecognizer (English only)
            guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
                statusMessage = "Speech recognition not authorized. Configure a provider in Settings → AI."
                return
            }
            statusMessage = "SFSpeech (English only) — configure Deepgram/OpenAI in Settings for Vietnamese support"
            let locale = Locale.current
            micRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
            systemRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
            startMicRecognition()
            startSystemRecognition()
            startAudioEngine()
            restartTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
                self?.startMicRecognition()
                self?.startSystemRecognition()
            }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        usingRealtimeProvider = false
        restartTimer?.invalidate()
        restartTimer = nil
        if let obs = deviceObserver { NotificationCenter.default.removeObserver(obs) }
        deviceObserver = nil
        partialMicText = ""
        partialSystemText = ""
        statusMessage = ""
        stopAudioEngine()
        activeProvider?.stop()
        activeProvider = nil
        micTask?.finish()
        systemTask?.finish()
        micRequest = nil
        systemRequest = nil
    }

    // Called from AVCapture — SFSpeech fallback path for system audio
    func append(_ sampleBuffer: CMSampleBuffer, from source: TranscriptSegment.Source) {
        guard isActive, !usingRealtimeProvider else { return }
        if source == .systemAudio {
            systemRequest?.appendAudioSampleBuffer(sampleBuffer)
        }
    }

    var fullTranscriptText: String {
        liveTranscript
            .sorted { $0.timestamp < $1.timestamp }
            .map { seg in
                let speaker = seg.source == .mic ? "You" : "Other"
                let m = Int(seg.timestamp) / 60
                let s = Int(seg.timestamp) % 60
                return String(format: "[%02d:%02d] \(speaker): \(seg.text)", m, s)
            }
            .joined(separator: "\n")
    }

    // MARK: - Audio Engine

    private func startAudioEngine() {
        stopAudioEngine()
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            statusMessage = "AVAudioEngine: invalid input format"
            return
        }

        if usingRealtimeProvider {
            activeProvider?.start(inputFormat: format)
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, self.isActive, !self.isMicMuted else { return }
            if self.usingRealtimeProvider {
                self.activeProvider?.send(buffer)
            } else {
                self.micRequest?.append(buffer)
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            if !usingRealtimeProvider {
                statusMessage = "AVAudioEngine running (\(Int(format.sampleRate))Hz)"
            }
        } catch {
            statusMessage = "AVAudioEngine failed: \(error.localizedDescription)"
        }
    }

    private func stopAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func restartAudioEngine() {
        guard isActive else { return }
        if usingRealtimeProvider {
            activeProvider?.stop()
            let provider = TranscriptionSettings.load()?.makeProvider()
            if let newProvider = provider {
                let t0 = startTime
                newProvider.onStatus = { [weak self] msg in
                    let s = self; DispatchQueue.main.async { s?.statusMessage = msg }
                }
                newProvider.onPartial = { [weak self] text in
                    let s = self; DispatchQueue.main.async { s?.partialMicText = text }
                }
                newProvider.onFinal = { [weak self] text in
                    guard let self else { return }
                    let now = Date().timeIntervalSince(t0)
                    DispatchQueue.main.async {
                        if var last = self.liveTranscript.last,
                           last.source == .mic,
                           now - last.timestamp < 3.0,
                           last.text.count < 60 {
                            last.text += " " + text
                            self.liveTranscript[self.liveTranscript.count - 1] = last
                        } else {
                            let seg = TranscriptSegment(source: .mic, text: text, timestamp: now)
                            self.liveTranscript.append(seg)
                        }
                        self.partialMicText = ""
                    }
                }
                activeProvider = newProvider
            }
        }
        startAudioEngine()
    }

    // MARK: - SFSpeech (fallback)

    private func startMicRecognition() {
        micTask?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = false
        req.shouldReportPartialResults = true
        micRequest = req
        micTask = micRecognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let error = error as NSError? {
                if error.code != 216 && error.code != 203 {
                    DispatchQueue.main.async { self.statusMessage = "MIC error \(error.code): \(error.localizedDescription)" }
                }
                return
            }
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            if result.isFinal {
                guard !text.isEmpty else { return }
                let seg = TranscriptSegment(
                    source: .mic, text: text,
                    timestamp: Date().timeIntervalSince(self.startTime)
                )
                DispatchQueue.main.async {
                    self.liveTranscript.append(seg)
                    self.partialMicText = ""
                }
            } else {
                DispatchQueue.main.async { self.partialMicText = text }
            }
        }
    }

    private func startSystemRecognition() {
        systemTask?.cancel()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = false
        req.shouldReportPartialResults = true
        systemRequest = req
        systemTask = systemRecognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if error != nil { return }
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            if result.isFinal {
                guard !text.isEmpty else { return }
                let seg = TranscriptSegment(
                    source: .systemAudio, text: text,
                    timestamp: Date().timeIntervalSince(self.startTime)
                )
                DispatchQueue.main.async {
                    self.liveTranscript.append(seg)
                    self.partialSystemText = ""
                }
            } else {
                DispatchQueue.main.async { self.partialSystemText = text }
            }
        }
    }
}
