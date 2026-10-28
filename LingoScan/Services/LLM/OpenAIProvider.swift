import Foundation
import LingoCore

/// OpenAI: `GET /v1/models` + Chat Completions con `response_format: json_schema` estricto.
/// `/v1/models` no publica precios ni modalidades: salen `nil` / `.unconfirmed` salvo `LLMCatalog`.
struct OpenAIProvider: LLMProvider {
    let id = LLMProviderID.openai
    let client: OpenAICompatibleClient

    init(transport: any HTTPTransport, log: any LLMLogSink) {
        client = OpenAICompatibleClient(
            config: OpenAICompatibleConfig(provider: .openai, baseURL: URL(string: "https://api.openai.com/v1")!,
                                           outputMode: .jsonSchemaStrict, maxTokensField: "max_completion_tokens",
                                           sendsReasoningEffort: true),
            transport: transport, log: log)
    }

    /// Modelos que no son de chat (embeddings, audio, imagen, moderación…) no sirven aquí.
    static let excludedMarkers = ["embedding", "tts", "whisper", "dall-e", "moderation", "audio", "realtime",
                                  "transcribe", "image", "search", "computer-use", "codex"]

    static func isChatModel(_ id: String) -> Bool {
        let chatPrefixes = ["gpt-", "chatgpt-", "o1", "o3", "o4"]
        return chatPrefixes.contains(where: id.hasPrefix) && !excludedMarkers.contains(where: id.contains)
    }

    /// Familias de razonamiento que aceptan `reasoning_effort` (heurística por prefijo).
    static func isReasoningModel(_ id: String) -> Bool {
        ["o1", "o3", "o4", "gpt-5"].contains(where: id.hasPrefix)
    }

    func listModels(apiKey: String) async throws -> [LLMModel] {
        let models = try await client.fetchModelObjects(apiKey: apiKey).compactMap { object -> LLMModel? in
            guard let id = object["id"] as? String, Self.isChatModel(id) else { return nil }
            let entry = LLMCatalog.entry(provider: .openai, modelID: id)
            return LLMModel(id: id, provider: .openai, displayName: id, imageSupport: entry?.imageSupport ?? .unconfirmed,
                            pricing: entry?.pricing, supportsReasoningControl: Self.isReasoningModel(id))
        }
        return LLMCatalog.applyRecommendations(models.sorted { $0.id < $1.id })
    }

    func analyze(_ request: FoodAnalysisRequest, model: LLMModel, apiKey: String) async throws -> FoodAnalysis {
        try await client.analyze(request, model: model, apiKey: apiKey)
    }

    func suggestRange(_ request: RangeSuggestionRequest, model: LLMModel, apiKey: String) async throws -> LLMRangeReply {
        try await client.suggestRange(request, model: model, apiKey: apiKey)
    }
}
