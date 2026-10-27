/// Devuelve el `LLMProvider` de cada `LLMProviderID` con un transporte inyectable (red real en la
/// app, respuestas grabadas en pruebas).
struct LLMProviderRegistry: Sendable {
    let transport: any HTTPTransport
    let log: any LLMLogSink

    init(transport: any HTTPTransport = URLSessionTransport(), log: any LLMLogSink = OSLogLLMSink()) {
        self.transport = transport
        self.log = log
    }

    func provider(for id: LLMProviderID) -> any LLMProvider {
        switch id {
        case .anthropic: AnthropicProvider(transport: transport, log: log)
        case .openai: OpenAIProvider(transport: transport, log: log)
        case .grok: GrokProvider(transport: transport, log: log)
        case .openrouter: OpenRouterProvider(transport: transport, log: log)
        case .deepseek: DeepSeekProvider(transport: transport, log: log)
        case .gemini: GeminiProvider(transport: transport, log: log)
        }
    }
}
