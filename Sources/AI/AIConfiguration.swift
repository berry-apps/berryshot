import Foundation
import CoreGraphics

public enum AIProviderType: String, CaseIterable, Sendable {
    case openAI = "OPENAI"
    case openRouter = "OPENROUTER"
    case gemini = "GEMINI"
    case claude = "CLAUDE"
    case xiaomiMimo = "XIAOMI_MIMO"
}

public struct AIConfiguration: Sendable {
    public let provider: AIProviderType
    public let apiKey: String
    public let model: String
    public let baseURL: String?
    public let plan: String? // "sub" or "token" for Xiaomi Mimo
    
    public init(provider: AIProviderType, apiKey: String, model: String, baseURL: String? = nil, plan: String? = nil) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.plan = plan
    }
    
    public static func loadSettings() -> AIConfiguration? {
        let defaults = UserDefaults.standard
        let providerStr = defaults.string(forKey: "ai_provider") ?? AIProviderType.xiaomiMimo.rawValue
        
        guard let provider = AIProviderType(rawValue: providerStr) else {
            return nil
        }
        
        let model = defaults.string(forKey: "ai_model") ?? "mimo-v2.5"
        var baseURL: String? = defaults.string(forKey: "ai_base_url")
        if baseURL?.isEmpty == true { baseURL = nil }
        
        let plan = defaults.string(forKey: "ai_plan") ?? "token"
        
        var apiKey = ""
        if let data = KeychainHelper.shared.read(key: "berryshot_ai_key_\(providerStr)"),
           let key = String(data: data, encoding: .utf8) {
            apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard !apiKey.isEmpty else {
            return nil
        }
        
        return AIConfiguration(provider: provider, apiKey: apiKey, model: model, baseURL: baseURL, plan: plan)
    }
}

public protocol LLMProvider {
    func generateText(prompt: String, image: CGImage?) async throws -> String
    func generateTextStream(prompt: String, image: CGImage?) -> AsyncThrowingStream<String, Error>
}

public enum AIError: Error {
    case invalidConfiguration
    case apiError(String)
    case invalidResponse
}

extension AIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid AI configuration."
        case .apiError(let message):
            return message
        case .invalidResponse:
            return "Invalid response from AI provider."
        }
    }
}
