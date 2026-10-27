import Foundation
import Testing
@testable import LingoScan

/// Transiciones de Ajustes → Asistente de comidas que `LLMSettingsViewModelTests` no cubre.
@MainActor
struct LLMSettingsExtraTransitionTests {
    private static let haiku = LLMModel(id: "claude-haiku-5-5", provider: .anthropic, displayName: "Haiku 5.5", imageSupport: .confirmed)
    private static let other = LLMModel(id: "claude-x", provider: .anthropic, displayName: "Otro")
    private static let newKey = "clave-de-prueba-nueva-0002"

    private struct Harness {
        let viewModel: LLMSettingsViewModel
        let keys: LLMKeyStore
        let settings: LLMSettingsStore
        let provider: FakeLLMProvider
    }

    private func make(key: String? = nil, chosen: LLMModel? = nil, provider: FakeLLMProvider? = nil) async throws -> Harness {
        let items = Dictionary(uniqueKeysWithValues: LLMProviderID.allCases.map { ($0, InMemorySecretItem()) })
        let keys = LLMKeyStore(itemFor: { items[$0]! })
        let settings = LLMSettingsStore(defaults: UserDefaults(suiteName: "llm-settings-extra-\(UUID().uuidString)")!)
        let fake = provider ?? FakeLLMProvider(catalog: [Self.other, Self.haiku])
        if let key { try await keys.save(key, for: .anthropic) }
        if let chosen { settings.setSelectedProvider(.anthropic); settings.setSelectedModel(chosen) }
        let viewModel = LLMSettingsViewModel(keys: keys, settings: settings, makeProvider: { _ in fake })
        await viewModel.load()
        return Harness(viewModel: viewModel, keys: keys, settings: settings, provider: fake)
    }

    @Test func comprobandoIsVisibleWhileTheCatalogIsRequestedAndBlocksSavingAgain() async throws {
        let provider = FakeLLMProvider(catalog: [Self.haiku])
        provider.listDelay = .seconds(5)
        let h = try await make(provider: provider)
        h.viewModel.keyInput = LLMFixtures.testKey
        let task = Task { await h.viewModel.saveAndCheck() }
        for _ in 0..<500 where h.viewModel.step != .comprobando { try await Task.sleep(for: .milliseconds(10)) }
        #expect(h.viewModel.step == .comprobando)
        #expect(h.viewModel.keyInput.isEmpty && !h.viewModel.canSaveKey)
        task.cancel()
        await task.value
    }

    @Test func changingTheKeyAndSavingANewOneReplacesItAndReachesTheCatalog() async throws {
        let h = try await make(key: LLMFixtures.testKey, chosen: Self.haiku)
        h.viewModel.changeKey()
        h.viewModel.keyInput = Self.newKey
        await h.viewModel.saveAndCheck()
        #expect(h.provider.listCalls == [Self.newKey])
        #expect(try await h.keys.key(for: .anthropic) == Self.newKey)
        #expect(h.viewModel.step == .catalogo)
        #expect(h.viewModel.selectedModel?.id == Self.haiku.id, "el modelo elegido se conserva")
    }

    @Test func rejectedNewKeyDuringChangeKeyDiscardsTheKeyStillStored() async throws {
        let h = try await make(key: LLMFixtures.testKey, chosen: Self.haiku, provider: FakeLLMProvider(listError: .unauthorized))
        h.viewModel.changeKey()
        h.viewModel.keyInput = Self.newKey
        await h.viewModel.saveAndCheck()
        #expect(h.viewModel.step == .sinClave && !h.viewModel.hasSavedKey)
        #expect(try await h.keys.key(for: .anthropic) == nil)
        #expect(h.viewModel.message == .failed(LLMError.unauthorized.description, keyKept: false))
    }

    @Test func refreshFailureStaysInCatalogKeepingTheKeyEvenWhenUnauthorized() async throws {
        let h = try await make()
        h.viewModel.keyInput = LLMFixtures.testKey
        await h.viewModel.saveAndCheck()
        h.provider.listError = .unauthorized
        await h.viewModel.refreshCatalog()
        #expect(h.viewModel.step == .catalogo)
        #expect(h.viewModel.hasSavedKey)
        #expect(try await h.keys.key(for: .anthropic) == LLMFixtures.testKey, "solo «Guardar y comprobar» descarta la clave")
        #expect(h.viewModel.message == .failed(LLMError.unauthorized.description, keyKept: true))
    }

    @Test func chooseIsIgnoredOutsideTheCatalogOrForAnotherProvidersModel() async throws {
        let h = try await make()
        h.viewModel.choose(Self.haiku)
        #expect(h.viewModel.step == .sinClave && h.viewModel.selectedModel == nil, "sin catálogo no se elige")
        h.viewModel.keyInput = LLMFixtures.testKey
        await h.viewModel.saveAndCheck()
        let foreign = LLMModel(id: "gpt-prueba", provider: .openai, displayName: "Prueba")
        h.viewModel.choose(foreign)
        #expect(h.viewModel.step == .catalogo && h.viewModel.selectedModel == nil)
    }

    @Test func changingProviderReloadsItsOwnStateWithoutNetworkAndKeepsTheOthersData() async throws {
        let h = try await make(key: LLMFixtures.testKey, chosen: Self.haiku)
        #expect(h.viewModel.step == .elegido)
        await h.viewModel.selectProvider(.openai)
        #expect(h.viewModel.providerChoice == .openai)
        #expect(h.viewModel.step == .sinClave && !h.viewModel.hasSavedKey && h.viewModel.selectedModel == nil)
        #expect(h.provider.listCalls.isEmpty)
        await h.viewModel.selectProvider(.anthropic)
        #expect(h.viewModel.step == .elegido && h.viewModel.selectedModel == Self.haiku)
    }

    @Test func forgetKeyOfOneProviderDoesNotTouchAnother() async throws {
        let h = try await make(key: LLMFixtures.testKey, chosen: Self.haiku)
        try await h.keys.save(Self.newKey, for: .openai)
        await h.viewModel.selectProvider(.openai)
        await h.viewModel.forgetKey()
        #expect(try await h.keys.key(for: .openai) == nil)
        #expect(try await h.keys.key(for: .anthropic) == LLMFixtures.testKey)
        #expect(h.settings.selectedModel(for: .anthropic) == Self.haiku)
    }

    @Test func cancelKeyChangeIsNotAvailableWithoutAChosenModel() async throws {
        let h = try await make(key: LLMFixtures.testKey)
        #expect(!h.viewModel.canCancelKeyChange)
        h.viewModel.cancelKeyChange()
        #expect(h.viewModel.step == .sinClave)
    }
}
