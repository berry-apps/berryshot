import Foundation

public class AIProviderFactory {
    public static func createProvider() -> LLMProvider? {
        guard let config = AIConfiguration.loadSettings() else {
            return nil
        }
        
        switch config.provider {
        case .openAI:
            return OpenAICompatibleProvider(config: config, defaultBaseURL: "https://api.openai.com/v1")
        case .openRouter:
            return OpenAICompatibleProvider(config: config, defaultBaseURL: "https://openrouter.ai/api/v1")
        case .gemini:
            // Needs Gemini-specific implementation, but many OpenAI SDKs work with Gemini OpenAI wrapper
            return OpenAICompatibleProvider(config: config, defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta/openai")
        case .claude:
            return ClaudeProvider(config: config)
        case .xiaomiMimo:
            let defaultMimoURL = config.plan?.lowercased() == "token" 
                ? "https://token-plan-sgp.xiaomimimo.com/v1" 
                : "https://api.xiaomimimo.com/v1"
            return OpenAICompatibleProvider(config: config, defaultBaseURL: defaultMimoURL)
        }
    }
}
