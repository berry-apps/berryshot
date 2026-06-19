import AVFoundation
import Foundation

final class DeepgramTranscriptionProvider: RealtimeTranscriptionProvider {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private let apiKey: String
    private let language: String
    private let model: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var sampleRate: Double = 48000

    init(apiKey: String, language: String = "auto", model: String = "nova-2") {
        self.apiKey = apiKey
        self.language = language
        self.model = model
    }

    func start(inputFormat: AVAudioFormat) {
        sampleRate = inputFormat.sampleRate
        connect()
    }

    func send(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        var int16 = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            int16[i] = Int16(max(-32768, min(32767, Int(channelData[0][i] * 32767))))
        }
        let data = int16.withUnsafeBytes { Data($0) }
        webSocketTask?.send(.data(data)) { _ in }
    }

    func stop() {
        let msg = "{\"type\":\"CloseStream\"}"
        webSocketTask?.send(.string(msg)) { _ in }
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession = nil
    }

    // MARK: - Private

    private func connect() {
        let lang = language == "auto" ? "multi" : language
        let urlStr = "wss://api.deepgram.com/v1/listen"
            + "?model=\(model)"
            + "&language=\(lang)"
            + "&encoding=linear16"
            + "&sample_rate=\(Int(sampleRate))"
            + "&channels=1"
            + "&punctuate=true"
            + "&interim_results=true"
            + "&endpointing=500"
            + "&utterance_end_ms=1000"

        guard let url = URL(string: urlStr) else { return }
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        urlSession = URLSession(configuration: .default)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        onStatus?("Deepgram connecting...")
        receiveLoop()
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receiveLoop()
            case .failure(let error):
                let code = (error as NSError).code
                if code != 57 && code != 54 {  // ignore "socket not connected" / "connection reset"
                    self.onStatus?("Deepgram error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let type = json["type"] as? String, type == "Metadata" {
            onStatus?("Deepgram ✓")
            return
        }

        guard let channel = json["channel"] as? [String: Any],
              let alts = channel["alternatives"] as? [[String: Any]],
              let transcript = alts.first?["transcript"] as? String,
              !transcript.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }

        let speechFinal = json["speech_final"] as? Bool ?? false
        let isFinal = json["is_final"] as? Bool ?? false

        if speechFinal || isFinal {
            onFinal?(transcript)
        } else {
            onPartial?(transcript)
        }
    }
}
