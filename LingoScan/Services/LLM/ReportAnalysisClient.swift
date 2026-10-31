import Foundation

/// Envía **una** petición de análisis de reporte al proveedor elegido y devuelve la respuesta ya con forma
/// (`ReportAnalysisParser`); el contenido lo juzga después `ReportAnalysisValidator`. Reutiliza los cuerpos y
/// lectores de respuesta de cada proveedor, pero con `max_tokens` de guía larga (12000, 16000 con razonamiento; nunca por
/// encima del tope que declare el catálogo del modelo) en vez del tope de 1024-2048 de las respuestas cortas, y con un
/// tiempo de espera de 180 s. Sin reintentos: cada toque cuesta una llamada.
struct ReportAnalysisClient: Sendable {
    static let timeout: TimeInterval = 180

    let transport: any HTTPTransport
    let log: any LLMLogSink

    init(transport: any HTTPTransport = URLSessionTransport(), log: any LLMLogSink = OSLogLLMSink()) {
        self.transport = transport
        self.log = log
    }

    func analyze(_ request: ReportAnalysisRequest, model: LLMModel, apiKey: String) async throws -> ReportAnalysisReply {
        let prompt = ReportAnalysisPrompt.prompt(for: request)
        switch model.provider {
        case .anthropic: return try await anthropic(prompt, model: model, apiKey: apiKey)
        case .gemini: return try await gemini(prompt, model: model, apiKey: apiKey)
        case .openai: return try await compatible(OpenAIProvider(transport: transport, log: log).client, prompt, model: model, apiKey: apiKey)
        case .grok: return try await compatible(GrokProvider(transport: transport, log: log).client, prompt, model: model, apiKey: apiKey)
        case .openrouter: return try await compatible(OpenRouterProvider(transport: transport, log: log).client, prompt, model: model, apiKey: apiKey)
        case .deepseek: return try await compatible(DeepSeekProvider(transport: transport, log: log).client, prompt, model: model, apiKey: apiKey)
        }
    }

    // MARK: - Anthropic

    private func anthropic(_ prompt: StructuredPrompt, model: LLMModel, apiKey: String) async throws -> ReportAnalysisReply {
        var body = AnthropicProvider.body(prompt: prompt, content: [["type": "text", "text": prompt.userText]], model: model)
        body["max_tokens"] = ReportAnalysisPrompt.outputLimit(
            AnthropicProvider.alwaysThinkingModels.contains(model.id)
                ? ReportAnalysisPrompt.reasoningMaxOutputTokens : ReportAnalysisPrompt.maxOutputTokens,
            for: model)
        let headers = ["x-api-key": apiKey, "anthropic-version": AnthropicProvider.apiVersion, "Accept": "application/json"]
        let data = try await send(url: AnthropicProvider.baseURL.appending(path: "messages"), headers: headers, body: body,
                                  provider: .anthropic, operation: "POST messages", apiKey: apiKey)
        switch try AnthropicProvider.structuredReply(from: data, toolName: prompt.toolName, apiKey: apiKey) {
        case .object(let input): return try ReportAnalysisParser.parse(object: input)
        case .text(let text): return try ReportAnalysisParser.parse(text: text)
        }
    }

    // MARK: - Gemini

    private func gemini(_ prompt: StructuredPrompt, model: LLMModel, apiKey: String) async throws -> ReportAnalysisReply {
        var body = GeminiProvider.body(prompt: prompt, parts: [["text": prompt.userText]])
        var generation = body["generationConfig"] as? [String: Any] ?? [:]
        generation["maxOutputTokens"] = ReportAnalysisPrompt.outputLimit(ReportAnalysisPrompt.reasoningMaxOutputTokens, for: model)
        body["generationConfig"] = generation
        let url = GeminiProvider.baseURL.appending(path: "models/\(model.id):generateContent")
        let data = try await send(url: url, headers: ["x-goog-api-key": apiKey, "Accept": "application/json"], body: body,
                                  provider: .gemini, operation: "POST generateContent", apiKey: apiKey)
        return try ReportAnalysisParser.parse(text: try GeminiProvider.structuredText(from: data, apiKey: apiKey))
    }

    // MARK: - Chat Completions (OpenAI, xAI, OpenRouter, DeepSeek)

    private func compatible(_ client: OpenAICompatibleClient, _ prompt: StructuredPrompt, model: LLMModel,
                            apiKey: String) async throws -> ReportAnalysisReply {
        var body = client.body(prompt: prompt, userContent: prompt.userText, model: model)
        let reasoning = client.config.sendsReasoningEffort && model.supportsReasoningControl
        body[client.config.maxTokensField] = ReportAnalysisPrompt.outputLimit(
            reasoning ? ReportAnalysisPrompt.reasoningMaxOutputTokens : ReportAnalysisPrompt.maxOutputTokens, for: model)
        let headers = client.config.extraHeaders.merging(["Authorization": "Bearer \(apiKey)", "Accept": "application/json"]) { _, new in new }
        let data = try await send(url: client.config.chatURL, headers: headers, body: body, provider: client.config.provider,
                                  operation: "POST chat/completions", apiKey: apiKey)
        return try ReportAnalysisParser.parse(text: try client.structuredText(from: data, apiKey: apiKey))
    }

    // MARK: - Envío

    private func send(url: URL, headers: [String: String], body: [String: Any], provider: LLMProviderID, operation: String,
                      apiKey: String) async throws -> Data {
        var request = try LLMHTTP.request(url: url, method: "POST", headers: headers, body: body)
        request.timeoutInterval = Self.timeout
        return try await LLMHTTP.perform(request, provider: provider, operation: operation, apiKey: apiKey,
                                         transport: transport, log: log)
    }
}
