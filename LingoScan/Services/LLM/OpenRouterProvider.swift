import Foundation
import LingoCore

/// OpenRouter: `GET /api/v1/models` publica precio por token (USD, cadena) y
/// `architecture.input_modalities` por modelo; se usan con `source: "catálogo de OpenRouter"`.
struct OpenRouterProvider: LLMProvider {
    let id = LLMProviderID.openrouter
    let client: OpenAICompatibleClient

    init(transport: any HTTPTransport, log: any LLMLogSink) {
        client = OpenAICompatibleClient(
            config: OpenAICompatibleConfig(provider: .openrouter, baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                                           outputMode: .jsonSchemaStrict, maxTokensField: "max_tokens",
                                           sendsReasoningEffort: false,
                                           extraHeaders: ["X-Title": "LingoScan"]),
            transport: transport, log: log)
    }

    static func model(from object: [String: Any]) -> LLMModel? {
        guard let id = object["id"] as? String else { return nil }
        let architecture = object["architecture"] as? [String: Any]
        let inputs = architecture?["input_modalities"] as? [String]
        let outputs = architecture?["output_modalities"] as? [String]
        if let outputs, !outputs.contains("text") { return nil }
        let imageSupport: ImageSupport = switch inputs {
        case let inputs? where inputs.contains("image"): .confirmed
        case .some: .none
        case nil: .unconfirmed
        }
        let rawPricing = object["pricing"] as? [String: Any]
        let input = LLMHTTP.perMillion(rawPricing?["prompt"])
        let output = LLMHTTP.perMillion(rawPricing?["completion"])
        let pricing = (input == nil && output == nil) ? nil
            : ModelPricing(inputUSDPerMTok: input, outputUSDPerMTok: output, source: LLMCatalog.openRouterSource, asOf: LLMCatalog.asOf)
        let parameters = object["supported_parameters"] as? [String] ?? []
        let maxOutput = (object["top_provider"] as? [String: Any])?["max_completion_tokens"] as? Int
        return LLMModel(id: id, provider: .openrouter, displayName: (object["name"] as? String) ?? id,
                        imageSupport: imageSupport, pricing: pricing, maxOutputTokens: maxOutput,
                        supportsReasoningControl: parameters.contains("reasoning"))
    }

    func listModels(apiKey: String) async throws -> [LLMModel] {
        let models = try await client.fetchModelObjects(apiKey: apiKey).compactMap(Self.model(from:))
        return LLMCatalog.applyRecommendations(models.sorted { $0.displayName < $1.displayName })
    }

    func analyze(_ request: FoodAnalysisRequest, model: LLMModel, apiKey: String) async throws -> FoodAnalysis {
        try await client.analyze(request, model: model, apiKey: apiKey)
    }
}
