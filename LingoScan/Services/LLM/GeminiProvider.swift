import Foundation
import LingoCore

/// Google Gemini (`generativelanguage.googleapis.com/v1beta`): catálogo `GET /models` (paginado con
/// `pageToken`), análisis con `models/{id}:generateContent`, imagen como `inlineData` JPEG y
/// `generationConfig.responseMimeType: application/json`. La clave va en la cabecera
/// `x-goog-api-key`, nunca en la URL.
struct GeminiProvider: LLMProvider {
    let id = LLMProviderID.gemini
    let transport: any HTTPTransport
    let log: any LLMLogSink

    static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    /// Holgura para el razonamiento, que en Gemini cuenta dentro de `maxOutputTokens`.
    static let maxOutputTokens = 4096
    static let refusalReasons: Set<String> = ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION",
                                              "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT"]

    init(transport: any HTTPTransport, log: any LLMLogSink) {
        self.transport = transport
        self.log = log
    }

    private func headers(apiKey: String) -> [String: String] {
        ["x-goog-api-key": apiKey, "Accept": "application/json"]
    }

    func listModels(apiKey: String) async throws -> [LLMModel] {
        var models: [LLMModel] = []
        var pageToken: String?
        for _ in 0..<10 {
            var components = URLComponents(url: Self.baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
                + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            let request = try LLMHTTP.request(url: components.url!, headers: headers(apiKey: apiKey))
            let data = try await LLMHTTP.perform(request, provider: id, operation: "GET models", apiKey: apiKey,
                                                 transport: transport, log: log)
            let object = try LLMHTTP.jsonObject(data)
            guard let page = object["models"] as? [[String: Any]] else {
                throw LLMError.invalidResponse(String(localized: "catálogo sin lista de modelos"))
            }
            models += page.compactMap(Self.model(from:))
            guard let next = object["nextPageToken"] as? String, !next.isEmpty else { break }
            pageToken = next
        }
        return LLMCatalog.applyRecommendations(models.sorted { $0.displayName < $1.displayName })
    }

    static func model(from object: [String: Any]) -> LLMModel? {
        guard let name = object["name"] as? String,
              (object["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true else { return nil }
        let id = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        let entry = LLMCatalog.entry(provider: .gemini, modelID: id)
        return LLMModel(id: id, provider: .gemini, displayName: (object["displayName"] as? String) ?? id,
                        imageSupport: entry?.imageSupport ?? .unconfirmed, pricing: entry?.pricing,
                        maxOutputTokens: object["outputTokenLimit"] as? Int,
                        supportsReasoningControl: object["thinking"] as? Bool ?? false)
    }

    func analyze(_ request: FoodAnalysisRequest, model: LLMModel, apiKey: String) async throws -> FoodAnalysis {
        try LLMHTTP.validate(request, model: model, provider: id)
        let url = Self.baseURL.appending(path: "models/\(model.id):generateContent")
        let urlRequest = try LLMHTTP.request(url: url, method: "POST", headers: headers(apiKey: apiKey),
                                             body: Self.body(for: request))
        let data = try await LLMHTTP.perform(urlRequest, provider: id, operation: "POST generateContent", apiKey: apiKey,
                                             transport: transport, log: log)
        return try Self.parse(data, apiKey: apiKey)
    }

    static func body(for request: FoodAnalysisRequest) -> [String: Any] {
        var parts: [[String: Any]] = [
            ["text": LLMPromptBuilder.userText(description: request.trimmedDescription, hasImage: request.hasImage)],
        ]
        if let image = request.imageJPEG, request.hasImage {
            parts.append(["inlineData": ["mimeType": "image/jpeg", "data": image.base64EncodedString()]])
        }
        return [
            "systemInstruction": ["parts": [["text": LLMPromptBuilder.systemPrompt(locale: request.locale)]]],
            "contents": [["role": "user", "parts": parts] as [String: Any]],
            "generationConfig": ["responseMimeType": "application/json", "maxOutputTokens": maxOutputTokens] as [String: Any],
        ]
    }

    static func parse(_ data: Data, apiKey: String) throws -> FoodAnalysis {
        let object = try LLMHTTP.jsonObject(data)
        if let block = (object["promptFeedback"] as? [String: Any])?["blockReason"] as? String {
            throw LLMError.refused(LLMHTTP.sanitize(block, apiKey: apiKey))
        }
        guard let candidate = (object["candidates"] as? [[String: Any]])?.first else {
            throw LLMError.invalidResponse(String(localized: "respuesta sin candidatos"))
        }
        let finish = candidate["finishReason"] as? String
        if finish == "MAX_TOKENS" { throw LLMError.incomplete("finishReason: MAX_TOKENS") }
        if let finish, refusalReasons.contains(finish) { throw LLMError.refused(finish) }
        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidResponse(String(localized: "respuesta vacía"))
        }
        return try LLMHTTP.parseAnalysis(text: text)
    }
}
