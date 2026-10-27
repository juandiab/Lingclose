import Foundation
import LingoCore

/// xAI (Grok): API compatible con Chat Completions en `https://api.x.ai/v1`, `Authorization: Bearer`,
/// `response_format: json_schema` estricto. Precios de `LLMCatalog` (docs.x.ai/docs/models).
struct GrokProvider: LLMProvider {
    let id = LLMProviderID.grok
    let client: OpenAICompatibleClient

    init(transport: any HTTPTransport, log: any LLMLogSink) {
        client = OpenAICompatibleClient(
            config: OpenAICompatibleConfig(provider: .grok, baseURL: URL(string: "https://api.x.ai/v1")!,
                                           outputMode: .jsonSchemaStrict, maxTokensField: "max_tokens",
                                           sendsReasoningEffort: false),
            transport: transport, log: log)
    }

    func listModels(apiKey: String) async throws -> [LLMModel] {
        let models = try await client.fetchModelObjects(apiKey: apiKey).compactMap { object -> LLMModel? in
            guard let id = object["id"] as? String, id.hasPrefix("grok"), !id.contains("imagine"), !id.contains("image") else {
                return nil
            }
            let entry = LLMCatalog.entry(provider: .grok, modelID: id)
            return LLMModel(id: id, provider: .grok, displayName: id, imageSupport: entry?.imageSupport ?? .unconfirmed,
                            pricing: entry?.pricing)
        }
        return LLMCatalog.applyRecommendations(models.sorted { $0.id < $1.id })
    }

    func analyze(_ request: FoodAnalysisRequest, model: LLMModel, apiKey: String) async throws -> FoodAnalysis {
        try await client.analyze(request, model: model, apiKey: apiKey)
    }
}
