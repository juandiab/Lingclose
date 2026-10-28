import Foundation
import LingoCore

/// DeepSeek: solo texto (`imageSupport: .none`), `https://api.deepseek.com`, `Authorization: Bearer`,
/// `response_format: {type: "json_object"}` con el esquema en el prompt. 402 = saldo insuficiente.
struct DeepSeekProvider: LLMProvider {
    let id = LLMProviderID.deepseek
    let client: OpenAICompatibleClient

    init(transport: any HTTPTransport, log: any LLMLogSink) {
        client = OpenAICompatibleClient(
            config: OpenAICompatibleConfig(provider: .deepseek, baseURL: URL(string: "https://api.deepseek.com")!,
                                           outputMode: .jsonObject, maxTokensField: "max_tokens",
                                           sendsReasoningEffort: false),
            transport: transport, log: log)
    }

    func listModels(apiKey: String) async throws -> [LLMModel] {
        let models = try await client.fetchModelObjects(apiKey: apiKey).compactMap { object -> LLMModel? in
            guard let id = object["id"] as? String else { return nil }
            return LLMModel(id: id, provider: .deepseek, displayName: (object["name"] as? String) ?? id,
                            imageSupport: .none, pricing: LLMCatalog.entry(provider: .deepseek, modelID: id)?.pricing,
                            maxOutputTokens: object["max_output_tokens"] as? Int,
                            supportsReasoningControl: object["effort"] != nil)
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
