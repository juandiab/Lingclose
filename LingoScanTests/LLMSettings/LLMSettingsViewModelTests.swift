import Foundation
import Testing
@testable import LingoScan

/// Una prueba por transición de la máquina de estados de Ajustes → Asistente de comidas.
@MainActor
struct LLMSettingsViewModelTests {
    private static let haiku = LLMModel(
        id: "claude-haiku-5-5", provider: .anthropic, displayName: "Haiku 5.5", imageSupport: .confirmed,
        pricing: ModelPricing(inputUSDPerMTok: 0.1, outputUSDPerMTok: 0.5, source: "https://example.test/precios", asOf: "2026-10"),
        recommendation: .recommended(reason: "Visión confirmada y precio bajo"))
    private static let other = LLMModel(id: "claude-x", provider: .anthropic, displayName: "Otro")

    private struct Harness {
        let viewModel: LLMSettingsViewModel
        let keys: LLMKeyStore
        let settings: LLMSettingsStore
        let provider: FakeLLMProvider
    }

    private func make(
        key: String? = nil, chosen: LLMModel? = nil, provider: FakeLLMProvider? = nil
    ) async throws -> Harness {
        let items = Dictionary(uniqueKeysWithValues: LLMProviderID.allCases.map { ($0, InMemorySecretItem()) })
        let keys = LLMKeyStore(itemFor: { items[$0]! })
        let settings = LLMSettingsStore(defaults: UserDefaults(suiteName: "llm-settings-\(UUID().uuidString)")!)
        let fake = provider ?? FakeLLMProvider(catalog: [Self.other, Self.haiku])
        if let key { try await keys.save(key, for: .anthropic) }
        if let chosen { settings.setSelectedProvider(.anthropic); settings.setSelectedModel(chosen) }
        let viewModel = LLMSettingsViewModel(keys: keys, settings: settings, makeProvider: { _ in fake })
        await viewModel.load()
        return Harness(viewModel: viewModel, keys: keys, settings: settings, provider: fake)
    }

    // MARK: Entrada a la pantalla

    @Test func startsInSinClaveWithoutNetwork() async throws {
        let h = try await make()
        #expect(h.viewModel.step == .sinClave && !h.viewModel.needsModelChoice)
        #expect(h.provider.listCalls.isEmpty)
    }

    @Test func keyAndModelSavedOpenDirectlyInElegidoWithoutNetwork() async throws {
        let h = try await make(key: LLMFixtures.testKey, chosen: Self.haiku)
        #expect(h.viewModel.step == .elegido)
        #expect(h.viewModel.selectedModel == Self.haiku)
        #expect(h.provider.listCalls.isEmpty)
    }

    @Test func keyWithoutModelStaysInSinClaveWithNoteAndNoNetwork() async throws {
        let h = try await make(key: LLMFixtures.testKey)
        #expect(h.viewModel.step == .sinClave && h.viewModel.needsModelChoice)
        #expect(h.provider.listCalls.isEmpty)
    }

    // MARK: 1 → 2 → 3

    @Test func saveAndCheckStoresTheKeyCallsTheCatalogAndShowsIt() async throws {
        let h = try await make()
        h.viewModel.keyInput = "  \(LLMFixtures.testKey) "
        await h.viewModel.saveAndCheck()
        #expect(h.provider.listCalls == [LLMFixtures.testKey])
        #expect(try await h.keys.key(for: .anthropic) == LLMFixtures.testKey)
        #expect(h.viewModel.step == .catalogo)
        #expect(h.viewModel.message == .accessible(count: 2))
        #expect(h.viewModel.keyInput.isEmpty, "la clave no queda en pantalla")
        #expect(h.viewModel.models.first?.id == Self.haiku.id, "recomendados primero")
    }

    @Test func unauthorizedReturnsToSinClaveShowsTheErrorAndDiscardsTheKey() async throws {
        let h = try await make(provider: FakeLLMProvider(listError: .unauthorized))
        h.viewModel.keyInput = LLMFixtures.testKey
        await h.viewModel.saveAndCheck()
        #expect(h.viewModel.step == .sinClave)
        #expect(h.viewModel.message == .failed(LLMError.unauthorized.description, keyKept: false))
        #expect(!h.viewModel.hasSavedKey)
        #expect(try await h.keys.key(for: .anthropic) == nil)
        #expect(!String(describing: h.viewModel.message).contains(LLMFixtures.testKey))
    }

    @Test func networkErrorReturnsToSinClaveKeepingTheKey() async throws {
        let h = try await make(provider: FakeLLMProvider(listError: .network("sin conexión")))
        h.viewModel.keyInput = LLMFixtures.testKey
        await h.viewModel.saveAndCheck()
        #expect(h.viewModel.step == .sinClave && h.viewModel.hasSavedKey && h.viewModel.needsModelChoice)
        #expect(h.viewModel.message == .failed(LLMError.network("sin conexión").description, keyKept: true))
        h.provider.listError = nil
        await h.viewModel.checkSavedKey()
        #expect(h.viewModel.step == .catalogo, "Comprobar y listar con la clave guardada")
    }

    @Test func emptyKeyCannotBeSaved() async throws {
        let h = try await make()
        h.viewModel.keyInput = "   "
        #expect(!h.viewModel.canSaveKey)
        await h.viewModel.saveAndCheck()
        #expect(h.provider.listCalls.isEmpty && h.viewModel.step == .sinClave)
    }

    // MARK: 3 → 4

    @Test func choosingAModelFoldsTheListAndPersists() async throws {
        let h = try await make()
        h.viewModel.keyInput = LLMFixtures.testKey
        await h.viewModel.saveAndCheck()
        h.viewModel.choose(Self.haiku)
        #expect(h.viewModel.step == .elegido)
        #expect(h.viewModel.selectedModel == Self.haiku)
        #expect(h.settings.selectedModel(for: .anthropic) == Self.haiku)
        #expect(h.settings.selectedProvider() == .anthropic)
    }

    @Test func searchFiltersByIdAndName() async throws {
        let h = try await make()
        h.viewModel.keyInput = LLMFixtures.testKey
        await h.viewModel.saveAndCheck()
        h.viewModel.searchText = "haiku"
        #expect(h.viewModel.filteredModels.map(\.id) == [Self.haiku.id])
        h.viewModel.searchText = "claude-x"
        #expect(h.viewModel.filteredModels.map(\.id) == [Self.other.id])
        h.viewModel.searchText = ""
        #expect(h.viewModel.filteredModels.count == 2)
    }

    // MARK: Desde 4

    @Test func changeModelReturnsToCatalogUsingTheDownloadedOne() async throws {
        let h = try await make()
        h.viewModel.keyInput = LLMFixtures.testKey
        await h.viewModel.saveAndCheck()
        h.viewModel.choose(Self.haiku)
        await h.viewModel.changeModel()
        #expect(h.viewModel.step == .catalogo)
        #expect(h.provider.listCalls.count == 1, "no vuelve a pedir el catálogo")
    }

    @Test func changeModelAfterReopeningRequestsTheCatalogOnce() async throws {
        let h = try await make(key: LLMFixtures.testKey, chosen: Self.haiku)
        await h.viewModel.changeModel()
        #expect(h.viewModel.step == .catalogo && h.provider.listCalls.count == 1)
    }

    @Test func changeModelFailureReturnsToElegidoWithTheError() async throws {
        let h = try await make(key: LLMFixtures.testKey, chosen: Self.haiku, provider: FakeLLMProvider(listError: .rateLimited))
        await h.viewModel.changeModel()
        #expect(h.viewModel.step == .elegido)
        #expect(h.viewModel.message == .failed(LLMError.rateLimited.description, keyKept: true))
    }

    @Test func refreshCatalogInsideCatalogAsksAgain() async throws {
        let h = try await make()
        h.viewModel.keyInput = LLMFixtures.testKey
        await h.viewModel.saveAndCheck()
        await h.viewModel.refreshCatalog()
        #expect(h.viewModel.step == .catalogo && h.provider.listCalls.count == 2)
    }

    @Test func changeKeyGoesBackToSinClaveAndCanBeCancelled() async throws {
        let h = try await make(key: LLMFixtures.testKey, chosen: Self.haiku)
        h.viewModel.changeKey()
        #expect(h.viewModel.step == .sinClave && h.viewModel.canCancelKeyChange)
        h.viewModel.cancelKeyChange()
        #expect(h.viewModel.step == .elegido)
    }

    @Test func forgetKeyDeletesKeyAndModelAndGoesBackToSinClave() async throws {
        let h = try await make(key: LLMFixtures.testKey, chosen: Self.haiku)
        await h.viewModel.forgetKey()
        #expect(h.viewModel.step == .sinClave && !h.viewModel.hasSavedKey && h.viewModel.selectedModel == nil)
        #expect(try await h.keys.key(for: .anthropic) == nil)
        #expect(h.settings.selectedModel(for: .anthropic) == nil)
    }

    // MARK: Formato

    @Test func priceAndImageTexts() {
        // Las frases cambian con el idioma del simulador; las cifras y la fuente, no.
        let price = Self.haiku.priceText
        #expect(price.contains("0,10 $") && price.contains("0,50 $") && price.contains("https://example.test/precios"))
        #expect(!Self.other.priceText.contains("$"), "sin precio publicado no se muestra ninguna cifra")
        #expect(Self.haiku.imageSupportText != Self.other.imageSupportText)
        #expect(LLMModel.dollars(0.075) == "0,075 $")
        #expect(LLMModel.dollars(15) == "15,00 $")
    }
}
