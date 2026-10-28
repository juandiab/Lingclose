import Foundation
import LingoCore

/// Anthropic Messages API (raw HTTP, `anthropic-version: 2026-10-21`). Salida estructurada con una
/// herramienta cuyo `input_schema` es el esquema de §2 y `tool_choice` forzado; imagen como bloque
/// `image` base64 `image/jpeg`; `max_tokens` 1024; sin `thinking`. Catálogo: `GET /v1/models`.
///
/// Los modelos con razonamiento siempre activo (Fable 5/5.1, Mythos, Opus 5.5, Sonnet 5.5) rechazan
/// con 400 tanto `thinking: disabled` como `tool_choice` forzado: con ellos se usa `tool_choice: auto`
/// + `strict: true` + la instrucción de usar la herramienta, y `effort: low` (fuente: skill claude-api).
struct AnthropicProvider: LLMProvider {
    let id = LLMProviderID.anthropic
    let transport: any HTTPTransport
    let log: any LLMLogSink

    static let baseURL = URL(string: "https://api.anthropic.com/v1")!
    static let apiVersion = "2026-10-21"
    static let maxTokens = 1024
    static let alwaysThinkingModels: Set<String> = [
        "claude-fable-5", "claude-fable-5-1", "claude-mythos-5", "claude-mythos-5-1", "claude-opus-5-5", "claude-sonnet-5-5",
    ]

    init(transport: any HTTPTransport, log: any LLMLogSink) {
        self.transport = transport
        self.log = log
    }

    private func headers(apiKey: String) -> [String: String] {
        ["x-api-key": apiKey, "anthropic-version": Self.apiVersion, "Accept": "application/json"]
    }

    // MARK: - Catálogo

    func listModels(apiKey: String) async throws -> [LLMModel] {
        var models: [LLMModel] = []
        var afterID: String?
        for _ in 0..<10 {  // como mucho 10 páginas
            var components = URLComponents(url: Self.baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "limit", value: "1000")]
                + (afterID.map { [URLQueryItem(name: "after_id", value: $0)] } ?? [])
            let request = try LLMHTTP.request(url: components.url!, headers: headers(apiKey: apiKey))
            let data = try await LLMHTTP.perform(request, provider: id, operation: "GET models", apiKey: apiKey,
                                                 transport: transport, log: log)
            let object = try LLMHTTP.jsonObject(data)
            guard let page = object["data"] as? [[String: Any]] else {
                throw LLMError.invalidResponse(String(localized: "catálogo sin lista de modelos"))
            }
            models += page.compactMap(Self.model(from:))
            guard object["has_more"] as? Bool == true, let last = object["last_id"] as? String else { break }
            afterID = last
        }
        return LLMCatalog.applyRecommendations(models)
    }

    static func model(from object: [String: Any]) -> LLMModel? {
        guard let id = object["id"] as? String else { return nil }
        let entry = LLMCatalog.entry(provider: .anthropic, modelID: id)
        let capabilities = object["capabilities"] as? [String: Any]
        let imageSupport: ImageSupport = switch (capabilities?["image_input"] as? [String: Any])?["supported"] as? Bool {
        case true?: .confirmed
        case false?: .none
        case nil: entry?.imageSupport ?? .unconfirmed
        }
        let effort = (capabilities?["effort"] as? [String: Any])?["supported"] as? Bool ?? false
        return LLMModel(id: id, provider: .anthropic, displayName: (object["display_name"] as? String) ?? id,
                        imageSupport: imageSupport, pricing: entry?.pricing,
                        maxOutputTokens: object["max_tokens"] as? Int, supportsReasoningControl: effort)
    }

    // MARK: - Análisis

    func analyze(_ request: FoodAnalysisRequest, model: LLMModel, apiKey: String) async throws -> FoodAnalysis {
        try LLMHTTP.validate(request, model: model, provider: id)
        let data = try await send(Self.body(for: request, model: model), apiKey: apiKey)
        switch try Self.structuredReply(from: data, toolName: LLMPromptBuilder.toolName, apiKey: apiKey) {
        case .object(let input): return try LLMHTTP.parseAnalysis(object: input)
        case .text(let text): return try LLMHTTP.parseAnalysis(text: text)
        }
    }

    func suggestRange(_ request: RangeSuggestionRequest, model: LLMModel, apiKey: String) async throws -> LLMRangeReply {
        try LLMHTTP.validate(model: model, provider: id)
        let prompt = RangeSuggestionPrompt.prompt(for: request)
        let data = try await send(Self.body(prompt: prompt, content: [["type": "text", "text": prompt.userText]], model: model),
                                  apiKey: apiKey)
        switch try Self.structuredReply(from: data, toolName: prompt.toolName, apiKey: apiKey) {
        case .object(let input): return try RangeSuggestionReplyParser.parse(object: input)
        case .text(let text): return try RangeSuggestionReplyParser.parse(text: text)
        }
    }

    private func send(_ body: [String: Any], apiKey: String) async throws -> Data {
        let urlRequest = try LLMHTTP.request(url: Self.baseURL.appending(path: "messages"), method: "POST",
                                             headers: headers(apiKey: apiKey), body: body)
        return try await LLMHTTP.perform(urlRequest, provider: id, operation: "POST messages", apiKey: apiKey,
                                         transport: transport, log: log)
    }

    static func body(for request: FoodAnalysisRequest, model: LLMModel) -> [String: Any] {
        let prompt = LLMPromptBuilder.foodPrompt(for: request)
        var content: [[String: Any]] = []
        if let image = request.imageJPEG, request.hasImage {
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]])
        }
        content.append(["type": "text", "text": prompt.userText])
        return body(prompt: prompt, content: content, model: model)
    }

    /// Cuerpo de `POST /v1/messages` con salida estructurada por herramienta (ver cabecera del tipo).
    static func body(prompt: StructuredPrompt, content: [[String: Any]], model: LLMModel) -> [String: Any] {
        let alwaysThinking = alwaysThinkingModels.contains(model.id)
        var tool: [String: Any] = [
            "name": prompt.toolName,
            "description": prompt.toolDescription,
            "input_schema": prompt.schema,
        ]
        var system = prompt.system
        var body: [String: Any] = [
            "model": model.id,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": content]],
        ]
        if alwaysThinking {
            tool["strict"] = true
            system += "\n\nEntrega el JSON llamando a la herramienta \(prompt.toolName); no escribas texto aparte."
            body["tool_choice"] = ["type": "auto", "disable_parallel_tool_use": true] as [String: Any]
            body["output_config"] = ["effort": "low"]
        } else {
            body["tool_choice"] = ["type": "tool", "name": prompt.toolName]
            body["thinking"] = ["type": "disabled"]
        }
        body["system"] = system
        body["tools"] = [tool]
        return body
    }

    enum StructuredReply {
        case object([String: Any])
        case text(String)
    }

    /// Datos de la herramienta `toolName` o, si el modelo escribió texto, ese texto. Mapea `stop_reason`.
    static func structuredReply(from data: Data, toolName: String, apiKey: String) throws -> StructuredReply {
        let object = try LLMHTTP.jsonObject(data)
        let stopReason = object["stop_reason"] as? String
        switch stopReason {
        case "max_tokens":
            throw LLMError.incomplete("stop_reason: max_tokens")
        case "refusal":
            let details = object["stop_details"] as? [String: Any]
            let reason = (details?["explanation"] as? String) ?? (details?["category"] as? String) ?? "refusal"
            throw LLMError.refused(LLMHTTP.sanitize(reason, apiKey: apiKey))
        default:
            break
        }
        let blocks = object["content"] as? [[String: Any]] ?? []
        if let toolUse = blocks.first(where: { $0["type"] as? String == "tool_use" && $0["name"] as? String == toolName }) {
            guard let input = toolUse["input"] as? [String: Any] else {
                throw LLMError.invalidResponse(String(localized: "herramienta sin datos"))
            }
            return .object(input)
        }
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidResponse(String(localized: "respuesta vacía"))
        }
        return .text(text)
    }

    /// Compatibilidad con las pruebas del análisis: `tool_use` de `record_food_analysis` o texto.
    static func parse(_ data: Data, apiKey: String) throws -> FoodAnalysis {
        switch try structuredReply(from: data, toolName: LLMPromptBuilder.toolName, apiKey: apiKey) {
        case .object(let input): return try LLMHTTP.parseAnalysis(object: input)
        case .text(let text): return try LLMHTTP.parseAnalysis(text: text)
        }
    }
}
