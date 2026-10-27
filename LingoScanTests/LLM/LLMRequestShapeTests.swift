import Foundation
import Testing
@testable import LingoScan

/// Forma de las peticiones de análisis por proveedor (salida estructurada, imagen, límites).
struct LLMRequestShapeTests {
    private func body(_ provider: LLMProviderID, model: LLMModel? = nil) async throws -> ([String: Any], URLRequest) {
        let transport = FixtureTransport(fixture: "\(provider.rawValue)-food")
        _ = try await LLMFixtures.provider(provider, transport: transport)
            .analyze(LLMFixtures.request(for: provider), model: model ?? LLMFixtures.model(for: provider), apiKey: LLMFixtures.testKey)
        let request = try #require(transport.requests.first)
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (body, request)
    }

    @Test func anthropicForcesTheToolWithoutThinking() async throws {
        let (body, request) = try await body(.anthropic)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == LLMFixtures.testKey)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(body["model"] as? String == "claude-haiku-5-5")
        #expect(body["max_tokens"] as? Int == 1024)
        #expect((body["thinking"] as? [String: Any])?["type"] as? String == "disabled")
        let choice = try #require(body["tool_choice"] as? [String: Any])
        #expect(choice["type"] as? String == "tool")
        #expect(choice["name"] as? String == LLMPromptBuilder.toolName)
        let tool = try #require((body["tools"] as? [[String: Any]])?.first)
        let schema = try #require(tool["input_schema"] as? [String: Any])
        #expect((schema["required"] as? [String])?.contains("unreadable") == true)
        #expect(body["temperature"] == nil)
        let content = try #require(((body["messages"] as? [[String: Any]])?.first)?["content"] as? [[String: Any]])
        let source = try #require(content.first?["source"] as? [String: Any])
        #expect(content.first?["type"] as? String == "image")
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "image/jpeg")
        #expect((body["system"] as? String)?.contains(LLMPromptBuilder.jsonSchemaLiteral) == true)
    }

    @Test func anthropicAlwaysThinkingModelsUseAutoToolChoice() async throws {
        let model = LLMModel(id: "claude-opus-5-5", provider: .anthropic, displayName: "Opus", imageSupport: .confirmed)
        let (body, _) = try await body(.anthropic, model: model)
        #expect((body["tool_choice"] as? [String: Any])?["type"] as? String == "auto")
        #expect(body["thinking"] == nil, "thinking disabled da 400 en estos modelos")
        #expect(((body["tools"] as? [[String: Any]])?.first)?["strict"] as? Bool == true)
        #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "low")
    }

    @Test func openAIUsesStrictJSONSchemaAndDataURL() async throws {
        let (body, request) = try await body(.openai)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(LLMFixtures.testKey)")
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["json_schema"] as? [String: Any])
        #expect(schema["strict"] as? Bool == true)
        #expect(schema["name"] as? String == LLMPromptBuilder.schemaName)
        #expect(body["max_completion_tokens"] as? Int == OpenAICompatibleClient.maxOutputTokens)
        #expect(body["reasoning_effort"] == nil, "el modelo de prueba no declara control de razonamiento")
        let user = try #require((body["messages"] as? [[String: Any]])?.last?["content"] as? [[String: Any]])
        let url = try #require((user.last?["image_url"] as? [String: Any])?["url"] as? String)
        #expect(url.hasPrefix("data:image/jpeg;base64,"))
    }

    @Test func openAIReasoningModelsGetLowEffort() async throws {
        let model = LLMModel(id: "gpt-5-mini", provider: .openai, displayName: "gpt-5-mini", imageSupport: .confirmed,
                             supportsReasoningControl: true)
        let (body, _) = try await body(.openai, model: model)
        #expect(body["reasoning_effort"] as? String == "low")
        #expect(body["max_completion_tokens"] as? Int == OpenAICompatibleClient.reasoningMaxOutputTokens)
    }

    @Test func deepSeekUsesJSONObjectAndTextOnly() async throws {
        let (body, request) = try await body(.deepseek)
        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect((body["response_format"] as? [String: Any])?["type"] as? String == "json_object")
        #expect(body["max_tokens"] as? Int != nil)
        #expect((body["messages"] as? [[String: Any]])?.last?["content"] is String, "sin partes de imagen")
        let system = try #require((body["messages"] as? [[String: Any]])?.first?["content"] as? String)
        #expect(system.lowercased().contains("json"), "json_object exige la palabra json en el prompt")
    }

    @Test func grokAndOpenRouterUseTheirEndpoints() async throws {
        let (_, grok) = try await body(.grok)
        #expect(grok.url?.absoluteString == "https://api.x.ai/v1/chat/completions")
        let (_, openRouter) = try await body(.openrouter)
        #expect(openRouter.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
    }

    @Test func geminiSendsInlineDataAndJSONMime() async throws {
        let (body, request) = try await body(.gemini)
        #expect(request.url?.absoluteString
            == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == LLMFixtures.testKey)
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        let parts = try #require((body["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])
        let inline = try #require(parts.last?["inlineData"] as? [String: Any])
        #expect(inline["mimeType"] as? String == "image/jpeg")
    }

    @Test func emptyRequestFailsBeforeCalling() async throws {
        let transport = FixtureTransport(fixture: "anthropic-food")
        await #expect(throws: LLMError.self) {
            try await LLMFixtures.provider(.anthropic, transport: transport)
                .analyze(FoodAnalysisRequest(description: "   "), model: LLMFixtures.model(for: .anthropic), apiKey: LLMFixtures.testKey)
        }
        #expect(transport.requests.isEmpty)
    }
}
