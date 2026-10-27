import Foundation
import LingoCore

/// Cliente común de Chat Completions (OpenAI, xAI, OpenRouter, DeepSeek). Autenticación
/// `Authorization: Bearer`, imagen como `image_url` con data URL `image/jpeg` en base64.
struct OpenAICompatibleClient: Sendable {
    static let maxOutputTokens = 2048
    static let reasoningMaxOutputTokens = 4096

    let config: OpenAICompatibleConfig
    let transport: any HTTPTransport
    let log: any LLMLogSink

    private func headers(apiKey: String) -> [String: String] {
        config.extraHeaders.merging(["Authorization": "Bearer \(apiKey)", "Accept": "application/json"]) { _, new in new }
    }

    /// `GET {base}/models` → `data[]` crudo, para que cada proveedor lo convierta.
    func fetchModelObjects(apiKey: String) async throws -> [[String: Any]] {
        let request = try LLMHTTP.request(url: config.modelsURL, headers: headers(apiKey: apiKey))
        let data = try await LLMHTTP.perform(request, provider: config.provider, operation: "GET models", apiKey: apiKey,
                                             transport: transport, log: log)
        guard let list = try LLMHTTP.jsonObject(data)["data"] as? [[String: Any]] else {
            throw LLMError.invalidResponse(String(localized: "catálogo sin lista de modelos"))
        }
        return list
    }

    func analyze(_ request: FoodAnalysisRequest, model: LLMModel, apiKey: String) async throws -> FoodAnalysis {
        try LLMHTTP.validate(request, model: model, provider: config.provider)
        let urlRequest = try LLMHTTP.request(url: config.chatURL, method: "POST", headers: headers(apiKey: apiKey),
                                             body: body(for: request, model: model))
        let data = try await LLMHTTP.perform(urlRequest, provider: config.provider, operation: "POST chat/completions",
                                             apiKey: apiKey, transport: transport, log: log)
        return try parse(data, apiKey: apiKey)
    }

    func body(for request: FoodAnalysisRequest, model: LLMModel) -> [String: Any] {
        let text = LLMPromptBuilder.userText(description: request.trimmedDescription, hasImage: request.hasImage)
        let userContent: Any
        if let image = request.imageJPEG, request.hasImage {
            userContent = [
                ["type": "text", "text": text],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(image.base64EncodedString())"]],
            ] as [[String: Any]]
        } else {
            userContent = text
        }
        let reasoning = config.sendsReasoningEffort && model.supportsReasoningControl
        var body: [String: Any] = [
            "model": model.id,
            "messages": [
                ["role": "system", "content": LLMPromptBuilder.systemPrompt(locale: request.locale)],
                ["role": "user", "content": userContent],
            ] as [[String: Any]],
            config.maxTokensField: reasoning ? Self.reasoningMaxOutputTokens : Self.maxOutputTokens,
        ]
        switch config.outputMode {
        case .jsonSchemaStrict:
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": LLMPromptBuilder.schemaName, "strict": true,
                                "schema": LLMPromptBuilder.strictSchema()] as [String: Any],
            ] as [String: Any]
        case .jsonObject:
            body["response_format"] = ["type": "json_object"]
        }
        if reasoning { body["reasoning_effort"] = "low" }
        return body
    }

    func parse(_ data: Data, apiKey: String) throws -> FoodAnalysis {
        let object = try LLMHTTP.jsonObject(data)
        // OpenRouter puede devolver un error del proveedor final con HTTP 200.
        if object["error"] != nil {
            let status = ((object["error"] as? [String: Any])?["code"] as? Int) ?? 502
            throw LLMHTTP.mapError(status: status, data: data, apiKey: apiKey)
        }
        guard let choice = (object["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else {
            throw LLMError.invalidResponse(String(localized: "respuesta sin choices"))
        }
        let finish = choice["finish_reason"] as? String
        if let refusal = message["refusal"] as? String, !refusal.isEmpty {
            throw LLMError.refused(LLMHTTP.sanitize(refusal, apiKey: apiKey))
        }
        switch finish {
        case "length": throw LLMError.incomplete("finish_reason: length")
        case "content_filter": throw LLMError.refused("content_filter")
        default: break
        }
        guard let content = message["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidResponse(String(localized: "respuesta vacía"))
        }
        return try LLMHTTP.parseAnalysis(text: content)
    }
}
