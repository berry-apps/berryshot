import AVFoundation
import Foundation

enum TranscriptionProviderType: String, CaseIterable {
    case deepgram
    case openaiRealtime = "openai_realtime"

    var displayName: String {
        switch self {
        case .deepgram: return "Deepgram"
        case .openaiRealtime: return "OpenAI Realtime"
        }
    }
}

protocol RealtimeTranscriptionProvider: AnyObject {
    var onPartial: ((String) -> Void)? { get set }
    var onFinal: ((String) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    func start(inputFormat: AVAudioFormat)
    func send(_ buffer: AVAudioPCMBuffer)
    func stop()
}

// MARK: - Settings helpers

struct TranscriptionSettings {
    let providerType: TranscriptionProviderType
    let apiKey: String
    let language: String  // "vi", "en", "ja", "auto"
    let model: String
    let baseURL: String

    var defaultModel: String {
        switch providerType {
        case .deepgram: return "nova-2"
        case .openaiRealtime: return "gpt-realtime-whisper"
        }
    }

    var resolvedModel: String { model.isEmpty ? defaultModel : model }

    static func load() -> TranscriptionSettings? {
        let defaults = UserDefaults.standard
        let providerRaw = defaults.string(forKey: "transcription_provider") ?? ""
        guard let type = TranscriptionProviderType(rawValue: providerRaw) else { return nil }

        let keychainKey: String
        switch type {
        case .deepgram: keychainKey = "berryshot_deepgram_key"
        case .openaiRealtime: keychainKey = "berryshot_whisper_key"
        }

        guard let data = KeychainHelper.shared.read(key: keychainKey),
              let key = String(data: data, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let lang = defaults.string(forKey: "transcription_language") ?? "vi"
        let model = defaults.string(forKey: "transcription_model") ?? ""
        let baseURL = defaults.string(forKey: "transcription_base_url") ?? ""
        
        return TranscriptionSettings(
            providerType: type,
            apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines),
            language: lang,
            model: model,
            baseURL: baseURL
        )
    }

    func makeProvider() -> RealtimeTranscriptionProvider {
        switch providerType {
        case .deepgram:
            return DeepgramTranscriptionProvider(apiKey: apiKey, language: language, model: resolvedModel)
        case .openaiRealtime:
            return OpenAIRealtimeProvider(apiKey: apiKey, language: language, model: resolvedModel, baseURL: baseURL)
        }
    }
}
