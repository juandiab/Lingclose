/// Proveedores de LLM que LingoScan sabe llamar. El `rawValue` es estable: se usa como cuenta del
/// Llavero (`LLMKeyStore`) y en `UserDefaults` (`LLMSettingsStore`).
enum LLMProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case anthropic, openai, grok, openrouter, deepseek, gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .openai: "OpenAI"
        case .grok: "xAI (Grok)"
        case .openrouter: "OpenRouter"
        case .deepseek: "DeepSeek"
        case .gemini: "Google Gemini"
        }
    }
}
