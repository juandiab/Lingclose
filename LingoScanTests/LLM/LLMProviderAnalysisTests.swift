import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// Análisis por proveedor con respuestas grabadas: comida, etiqueta, 401, 429, truncado, JSON roto.
struct LLMProviderAnalysisTests {
    static let providers = LLMProviderID.allCases

    @Test(arguments: providers)
    func foodResponseBecomesAnalysis(provider: LLMProviderID) async throws {
        let transport = FixtureTransport(fixture: "\(provider.rawValue)-food")
        let analysis = try await LLMFixtures.provider(provider, transport: transport)
            .analyze(LLMFixtures.request(for: provider), model: LLMFixtures.model(for: provider), apiKey: LLMFixtures.testKey)
        #expect(analysis.kind == .food)
        #expect(analysis.name == "Arepa con queso")
        #expect(analysis.basis == .estimatedServing(description: "1 arepa mediana", grams: 120))
        #expect(analysis.baseNutrients == Nutrients(kcal: 320, carbsG: 38, proteinG: 11, fatG: 14))
        #expect(analysis.confidence == 0.7)
        #expect(transport.requests.count == 1)
    }

    @Test(arguments: providers)
    func labelResponseKeepsBasisAndUnknowns(provider: LLMProviderID) async throws {
        let transport = FixtureTransport(fixture: "\(provider.rawValue)-label")
        let analysis = try await LLMFixtures.provider(provider, transport: transport)
            .analyze(LLMFixtures.request(for: provider), model: LLMFixtures.model(for: provider), apiKey: LLMFixtures.testKey)
        #expect(analysis.kind == .nutritionLabel)
        #expect(analysis.basis == .per100g)
        #expect(analysis.baseNutrients.kcal == 450)
        #expect(analysis.baseNutrients.carbsG == 60)
        #expect(analysis.baseNutrients.proteinG == nil, "ilegible sigue desconocido, nunca 0")
        #expect(analysis.baseNutrients.fatG == 20)
        #expect(analysis.unreadableFields == ["protein_g"])
    }

    @Test(arguments: providers)
    func status401IsUnauthorized(provider: LLMProviderID) async throws {
        let transport = FixtureTransport(status: 401, fixture: "\(provider.rawValue)-401")
        await #expect(throws: LLMError.unauthorized) {
            try await LLMFixtures.provider(provider, transport: transport)
                .analyze(LLMFixtures.request(for: provider), model: LLMFixtures.model(for: provider), apiKey: LLMFixtures.testKey)
        }
        #expect(transport.requests.count == 1, "sin reintentos")
    }

    @Test(arguments: providers)
    func status429IsRateLimited(provider: LLMProviderID) async throws {
        let transport = FixtureTransport(status: 429, fixture: "\(provider.rawValue)-429")
        await #expect(throws: LLMError.rateLimited) {
            try await LLMFixtures.provider(provider, transport: transport)
                .analyze(LLMFixtures.request(for: provider), model: LLMFixtures.model(for: provider), apiKey: LLMFixtures.testKey)
        }
        #expect(transport.requests.count == 1, "sin reintentos")
    }

    @Test(arguments: providers)
    func truncatedResponseIsIncomplete(provider: LLMProviderID) async throws {
        let transport = FixtureTransport(fixture: "\(provider.rawValue)-truncated")
        do {
            _ = try await LLMFixtures.provider(provider, transport: transport)
                .analyze(LLMFixtures.request(for: provider), model: LLMFixtures.model(for: provider), apiKey: LLMFixtures.testKey)
            Issue.record("debía fallar")
        } catch let error as LLMError {
            guard case .incomplete = error else { Issue.record("esperaba incomplete, llegó \(error)"); return }
        }
    }

    @Test(arguments: providers)
    func brokenJSONIsInvalidResponse(provider: LLMProviderID) async throws {
        let transport = FixtureTransport(fixture: "\(provider.rawValue)-broken")
        do {
            _ = try await LLMFixtures.provider(provider, transport: transport)
                .analyze(LLMFixtures.request(for: provider), model: LLMFixtures.model(for: provider), apiKey: LLMFixtures.testKey)
            Issue.record("debía fallar")
        } catch let error as LLMError {
            guard case .invalidResponse = error else { Issue.record("esperaba invalidResponse, llegó \(error)"); return }
        }
    }

    @Test(arguments: providers)
    func imageWithoutConfirmedVisionFailsBeforeCalling(provider: LLMProviderID) async throws {
        let transport = FixtureTransport(fixture: "\(provider.rawValue)-food")
        let request = FoodAnalysisRequest(imageJPEG: LLMFixtures.fakeJPEG, description: nil, locale: "es-CO")
        for support in [ImageSupport.unconfirmed, .none] {
            await #expect(throws: LLMError.modelLacksVision) {
                try await LLMFixtures.provider(provider, transport: transport)
                    .analyze(request, model: LLMFixtures.model(for: provider, imageSupport: support), apiKey: LLMFixtures.testKey)
            }
        }
        #expect(transport.requests.isEmpty, "no se gasta una petición")
    }

    @Test func geminiInvalidKeyOn400IsUnauthorized() async throws {
        let transport = FixtureTransport(status: 400, fixture: "gemini-401")
        await #expect(throws: LLMError.unauthorized) {
            try await LLMFixtures.provider(.gemini, transport: transport)
                .analyze(LLMFixtures.request(for: .gemini), model: LLMFixtures.model(for: .gemini), apiKey: LLMFixtures.testKey)
        }
    }

    @Test func deepSeek402IsQuotaExceeded() async throws {
        let transport = FixtureTransport(status: 402, fixture: "deepseek-402")
        await #expect(throws: LLMError.quotaExceeded) {
            try await LLMFixtures.provider(.deepseek, transport: transport)
                .analyze(LLMFixtures.request(for: .deepseek), model: LLMFixtures.model(for: .deepseek), apiKey: LLMFixtures.testKey)
        }
    }

    @Test func openRouterErrorInsideHTTP200IsMapped() async throws {
        let transport = FixtureTransport(fixture: "openrouter-200-error")
        await #expect(throws: LLMError.quotaExceeded) {
            try await LLMFixtures.provider(.openrouter, transport: transport)
                .analyze(LLMFixtures.request(for: .openrouter), model: LLMFixtures.model(for: .openrouter), apiKey: LLMFixtures.testKey)
        }
    }

    @Test func networkFailureIsNetworkError() async throws {
        let transport = FixtureTransport([])
        do {
            _ = try await LLMFixtures.provider(.anthropic, transport: transport)
                .analyze(LLMFixtures.request(for: .anthropic), model: LLMFixtures.model(for: .anthropic), apiKey: LLMFixtures.testKey)
            Issue.record("debía fallar")
        } catch let error as LLMError {
            guard case .network = error else { Issue.record("esperaba network, llegó \(error)"); return }
        }
    }
}
