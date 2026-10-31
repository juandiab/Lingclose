import Foundation
import Testing
@testable import LingoScan

/// Proveedor y modelo elegidos en `UserDefaults`, nunca la clave.
struct LLMSettingsStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "lingoscan.tests.llm.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func roundTripsProviderAndModel() {
        let defaults = makeDefaults()
        let store = LLMSettingsStore(defaults: defaults)
        #expect(store.selectedProvider() == nil)
        store.setSelectedProvider(.anthropic)
        let model = LLMModel(id: "claude-haiku-5-5", provider: .anthropic, displayName: "Claude Haiku 5.5",
                             imageSupport: .confirmed,
                             pricing: ModelPricing(inputUSDPerMTok: 0.1, outputUSDPerMTok: 0.5, source: "s", asOf: "2026-10"),
                             recommendation: .recommended(reason: "r"), maxOutputTokens: 128_000, supportsReasoningControl: true)
        store.setSelectedModel(model)

        let reopened = LLMSettingsStore(defaults: defaults)
        #expect(reopened.selectedProvider() == .anthropic)
        #expect(reopened.selectedModel(for: .anthropic) == model)
        #expect(reopened.selectedModel(for: .openai) == nil)
        reopened.clearSelectedModel(for: .anthropic)
        #expect(reopened.selectedModel(for: .anthropic) == nil)
        reopened.setSelectedProvider(nil)
        #expect(reopened.selectedProvider() == nil)
    }

    @Test func neverStoresAnythingThatLooksLikeAKey() throws {
        let defaults = makeDefaults()
        let store = LLMSettingsStore(defaults: defaults)
        store.setSelectedProvider(.openai)
        store.setSelectedModel(LLMModel(id: "gpt-5-mini", provider: .openai, displayName: "gpt-5-mini"))
        let stored = defaults.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("lingoscan.llm.") }
            .map { "\($0.key)=\($0.value)" + (($0.value as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "") }
            .joined()
        #expect(!stored.isEmpty)
        #expect(!stored.lowercased().contains("key\""))
        #expect(!stored.contains("sk-"))
    }

    // MARK: - T-33: interruptores del contexto del análisis

    @Test func analysisSharingIsOffByDefaultAndPersists() {
        let defaults = makeDefaults()
        let store = LLMSettingsStore(defaults: defaults)
        #expect(store.analysisSharing() == .none)
        #expect(store.analysisSharing().isEmpty)

        store.setAnalysisSharing(.meals, isOn: true)
        store.setAnalysisSharing(.profile, isOn: true)
        let reopened = LLMSettingsStore(defaults: defaults)
        #expect(reopened.analysisSharing() == ReportAnalysisSharing(meals: true, sleepActivity: false, profile: true))
        #expect(reopened.analysisSharing().enabled == [.meals, .profile])
        #expect(defaults.bool(forKey: "lingoscan.llm.analysis.share_meals.v1"))
        #expect(!defaults.bool(forKey: "lingoscan.llm.analysis.share_sleep_activity.v1"))
        #expect(defaults.bool(forKey: "lingoscan.llm.analysis.share_profile.v1"))

        reopened.setAnalysisSharing(.meals, isOn: false)
        reopened.setAnalysisSharing(.sleepActivity, isOn: true)
        #expect(LLMSettingsStore(defaults: defaults).analysisSharing() == ReportAnalysisSharing(sleepActivity: true, profile: true))
    }
}
