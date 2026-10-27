import Foundation
import Testing
@testable import LingoScan

/// Catálogo autenticado de cada proveedor → `[LLMModel]` con precio, imágenes y recomendación.
struct LLMProviderCatalogTests {
    private func models(_ provider: LLMProviderID) async throws -> ([LLMModel], FixtureTransport) {
        let transport = FixtureTransport(fixture: "\(provider.rawValue)-models")
        let models = try await LLMFixtures.provider(provider, transport: transport).listModels(apiKey: LLMFixtures.testKey)
        return (models, transport)
    }

    @Test func anthropicCatalog() async throws {
        let (models, transport) = try await models(.anthropic)
        #expect(models.map(\.id) == ["claude-haiku-5-5", "claude-opus-5-5", "claude-legacy-text"])
        let haiku = try #require(models.first)
        #expect(haiku.displayName == "Claude Haiku 5.5")
        #expect(haiku.imageSupport == .confirmed)
        #expect(haiku.pricing == ModelPricing(inputUSDPerMTok: 0.10, outputUSDPerMTok: 0.50,
                                              source: LLMCatalog.anthropicSource, asOf: "2026-10"))
        #expect(haiku.maxOutputTokens == 128_000)
        #expect(haiku.supportsReasoningControl)
        guard case .recommended = haiku.recommendation else { Issue.record("Haiku 5.5 es la recomendación por defecto"); return }
        #expect(models[1].recommendation == .unknown)
        #expect(models[1].pricing?.inputUSDPerMTok == 4)
        // Sin `capabilities` ni entrada en el catálogo: no confirmado y sin precio.
        #expect(models[2].imageSupport == .unconfirmed)
        #expect(models[2].pricing == nil)
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=1000")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == LLMFixtures.testKey)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == AnthropicProvider.apiVersion)
    }

    @Test func openAICatalogKeepsOnlyChatModelsWithoutInventedData() async throws {
        let (models, transport) = try await models(.openai)
        #expect(models.map(\.id) == ["gpt-4.1", "gpt-5-mini"])
        // gpt-5-mini: página del modelo "Input modalities: text, image" y precio publicado → recomendado (único con imágenes confirmadas).
        let mini = try #require(models.first { $0.id == "gpt-5-mini" })
        #expect(mini.imageSupport == .confirmed && mini.pricing?.inputUSDPerMTok == 0.25 && mini.pricing?.outputUSDPerMTok == 2.00)
        #expect(mini.pricing?.source == LLMCatalog.openAIPricingSource)
        if case .recommended = mini.recommendation {} else { Issue.record("gpt-5-mini debería ser el recomendado") }
        // gpt-4.1: precio publicado, imágenes sin confirmar en su página → no se recomienda ni se inventa.
        let full = try #require(models.first { $0.id == "gpt-4.1" })
        #expect(full.imageSupport == .unconfirmed && full.pricing?.inputUSDPerMTok == 2 && full.recommendation == .unknown)
        #expect(models.first { $0.id == "gpt-5-mini" }?.supportsReasoningControl == true)
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(LLMFixtures.testKey)")
    }

    @Test func grokCatalogUsesPublishedPrices() async throws {
        let (models, transport) = try await models(.grok)
        #expect(models.map(\.id) == ["grok-4.3", "grok-4.7"])
        let grok47 = try #require(models.first { $0.id == "grok-4.7" })
        #expect(grok47.imageSupport == .confirmed)
        #expect(grok47.pricing == ModelPricing(inputUSDPerMTok: 2, outputUSDPerMTok: 6, source: LLMCatalog.xaiSource, asOf: "2026-10"))
        guard case .recommended = grok47.recommendation else { Issue.record("grok-4.7 es el único con visión confirmada"); return }
        let grok43 = try #require(models.first { $0.id == "grok-4.3" })
        #expect(grok43.imageSupport == .unconfirmed)
        #expect(grok43.recommendation == .unknown)
        #expect(transport.requests.first?.url?.absoluteString == "https://api.x.ai/v1/models")
    }

    @Test func openRouterCatalogUsesItsPricesAndModalities() async throws {
        let (models, transport) = try await models(.openrouter)
        #expect(models.map(\.id) == ["anthropic/claude-haiku-5-5", "deepseek/deepseek-flash"], "los que no devuelven texto se descartan")
        let haiku = models[0]
        #expect(haiku.imageSupport == .confirmed)
        #expect(haiku.pricing == ModelPricing(inputUSDPerMTok: 0.1, outputUSDPerMTok: 0.5,
                                              source: LLMCatalog.openRouterSource, asOf: "2026-10"))
        #expect(haiku.maxOutputTokens == 128_000)
        #expect(haiku.supportsReasoningControl)
        guard case .recommended = haiku.recommendation else { Issue.record("con visión y precio debía recomendarse"); return }
        let flash = models[1]
        #expect(flash.imageSupport == .none)
        #expect(flash.pricing?.inputUSDPerMTok == 0.27)
        #expect(flash.pricing?.outputUSDPerMTok == 1.1)
        guard case .notRecommended = flash.recommendation else { Issue.record("sin imágenes no se recomienda"); return }
        #expect(transport.requests.first?.url?.absoluteString == "https://openrouter.ai/api/v1/models")
    }

    @Test func deepSeekCatalogIsTextOnly() async throws {
        let (models, transport) = try await models(.deepseek)
        #expect(models.map(\.id) == ["deepseek-flash", "deepseek-v4-pro"])
        #expect(models.allSatisfy { $0.imageSupport == .none && $0.pricing == nil })
        #expect(models.allSatisfy { if case .notRecommended = $0.recommendation { true } else { false } })
        #expect(models[0].displayName == "DeepSeek Flash")
        #expect(models[0].maxOutputTokens == 8192)
        #expect(models[1].supportsReasoningControl)
        #expect(transport.requests.first?.url?.absoluteString == "https://api.deepseek.com/models")
    }

    @Test func geminiCatalogKeepsGenerateContentModels() async throws {
        let (models, transport) = try await models(.gemini)
        #expect(models.map(\.id) == ["gemini-3.6-flash"])
        #expect(models[0].displayName == "Gemini 3.6 Flash")
        #expect(models[0].maxOutputTokens == 65_536)
        #expect(models[0].supportsReasoningControl)
        // Guía oficial de comprensión de imágenes: todas las versiones de Gemini son multimodales; precio de la página de precios.
        #expect(models[0].imageSupport == .confirmed)
        #expect(models[0].pricing?.inputUSDPerMTok == 0.75 && models[0].pricing?.outputUSDPerMTok == 3.75)
        #expect(models[0].pricing?.source == LLMCatalog.geminiPricingSource)
        if case .recommended = models[0].recommendation {} else { Issue.record("único modelo con imágenes y precio: recomendado") }
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == LLMFixtures.testKey)
    }

    @Test func catalogUnauthorizedIsMapped() async throws {
        for provider in LLMProviderID.allCases {
            let transport = FixtureTransport(status: 401, fixture: "\(provider.rawValue)-401")
            await #expect(throws: LLMError.unauthorized) {
                try await LLMFixtures.provider(provider, transport: transport).listModels(apiKey: LLMFixtures.testKey)
            }
        }
    }
}
