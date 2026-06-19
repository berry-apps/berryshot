@preconcurrency import AVFoundation
import Foundation

final class OpenAIRealtimeProvider: RealtimeTranscriptionProvider, @unchecked Sendable {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private let apiKey: String
    private let language: String
    private let model: String
    private let baseURL: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var converter: AVAudioConverter?
    private var currentUtterance = ""
    private var uncommittedSamples: Int = 0

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24000,
        channels: 1,
        interleaved: true
    )!

    init(apiKey: String, language: String = "auto", model: String = "gpt-realtime-whisper", baseURL: String = "") {
        self.apiKey = apiKey
        self.language = language
        self.model = model
        self.baseURL = baseURL
    }

    func start(inputFormat: AVAudioFormat) {
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        createTranscriptionSession()
    }

    func send(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outFrames > 0,
              let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames)
        else { return }

        class State: @unchecked Sendable {
            var consumed = false
            let buffer: AVAudioPCMBuffer
            init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        }
        let state = State(buffer: buffer)
        
        var convError: NSError?
        converter.convert(to: converted, error: &convError) { _, statusPtr in
            if state.consumed { statusPtr.pointee = .noDataNow; return nil }
            state.consumed = true
            statusPtr.pointee = .haveData
            return state.buffer
        }
        guard convError == nil, converted.frameLength > 0 else { return }

        let byteCount = Int(converted.frameLength) * 2
        let audioData = Data(bytes: converted.int16ChannelData![0], count: byteCount)
        let base64 = audioData.base64EncodedString()
        let event = "{\"type\":\"input_audio_buffer.append\",\"audio\":\"\(base64)\"}"
        webSocketTask?.send(.string(event)) { _ in }

        uncommittedSamples += Int(converted.frameLength)
        // Commit every ~1.5s of audio (36000 samples at 24kHz)
        if uncommittedSamples >= 36000 {
            webSocketTask?.send(.string("{\"type\":\"input_audio_buffer.commit\"}")) { _ in }
            uncommittedSamples = 0
        }
    }

    func stop() {
        if uncommittedSamples > 0 {
            webSocketTask?.send(.string("{\"type\":\"input_audio_buffer.commit\"}")) { _ in }
        }
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession = nil
        converter = nil
        currentUtterance = ""
        uncommittedSamples = 0
    }

    // MARK: - Private

    private func createTranscriptionSession() {
        var apiBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiBase.isEmpty {
            apiBase = "https://api.openai.com/v1"
        }
        if apiBase.hasPrefix("wss://") { apiBase = "https://" + apiBase.dropFirst(6) }
        if apiBase.hasPrefix("ws://") { apiBase = "http://" + apiBase.dropFirst(5) }
        while apiBase.hasSuffix("/") { apiBase = String(apiBase.dropLast()) }

        let urlStr = apiBase + "/realtime/client_secrets"
        guard let url = URL(string: urlStr) else {
            onStatus?("Invalid URL: \(urlStr)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var transcriptionConfig: [String: Any] = ["model": model]
        if language != "auto" {
            transcriptionConfig["language"] = language
        }

        let body: [String: Any] = [
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24000],
                        "transcription": transcriptionConfig
                    ]
                ]
            ] as [String: Any]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        onStatus?("Creating transcription session...")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error = error {
                self.onStatus?("Session failed: \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                self.onStatus?("Empty response")
                return
            }

            print("[OpenAI] client_secrets response: \(String(data: data, encoding: .utf8) ?? "nil")")

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                    self.onStatus?("OpenAI: \(msg)")
                    return
                }
                if let ek = json["value"] as? String {
                    self.connectWithEphemeralKey(ek)
                    return
                }
            }
            self.onStatus?("Unexpected response")
        }.resume()
    }

    private func connectWithEphemeralKey(_ ek: String) {
        var wsBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if wsBase.isEmpty {
            wsBase = "wss://api.openai.com/v1/realtime"
        } else {
            if wsBase.hasPrefix("https://") { wsBase = "wss://" + wsBase.dropFirst(8) }
            if wsBase.hasPrefix("http://") { wsBase = "ws://" + wsBase.dropFirst(7) }
            while wsBase.hasSuffix("/") { wsBase = String(wsBase.dropLast()) }
            if !wsBase.hasSuffix("/realtime") { wsBase += "/realtime" }
        }

        guard let url = URL(string: wsBase) else {
            onStatus?("Invalid WebSocket URL: \(wsBase)")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(ek)", forHTTPHeaderField: "Authorization")

        urlSession = URLSession(configuration: .default)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        onStatus?("OpenAI Realtime connecting...")
        receiveLoop()
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    print("OpenAI WS Receive: \(text.prefix(200))")
                    self.handle(text)
                }
                self.receiveLoop()
            case .failure(let error):
                let code = (error as NSError).code
                print("OpenAI WS Error: \(error)")
                if code != 57 && code != 54 {
                    self.onStatus?("OpenAI Realtime error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        print("[OpenAI Realtime] Event: \(type)")

        switch type {
        case "session.created", "session.updated", "transcription_session.created":
            onStatus?("OpenAI Realtime ✓")

        // Transcription session events (whisper)
        case "conversation.item.input_audio_transcription.delta":
            if let delta = json["delta"] as? String, !delta.isEmpty {
                currentUtterance += delta
                onPartial?(currentUtterance)
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                onFinal?(transcript)
            }
            currentUtterance = ""

        // Realtime session events (gpt-realtime / gpt-realtime-2)
        case "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String, !delta.isEmpty {
                currentUtterance += delta
                onPartial?(currentUtterance)
            }

        case "response.output_audio_transcript.done":
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                onFinal?(transcript)
            }
            currentUtterance = ""

        // VAD events - useful for debugging
        case "input_audio_buffer.speech_started":
            print("[OpenAI Realtime] Speech started")
        case "input_audio_buffer.speech_stopped":
            print("[OpenAI Realtime] Speech stopped")
        case "input_audio_buffer.committed":
            print("[OpenAI Realtime] Audio committed")

        case "error":
            if let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                print("[OpenAI Realtime] Error: \(msg)")
                onStatus?("OpenAI error: \(msg)")
            }

        default:
            print("[OpenAI Realtime] Unhandled event: \(type)")
            break
        }
    }
}
