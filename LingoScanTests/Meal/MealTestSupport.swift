import Foundation
import LingoCore
@testable import LingoScan

/// Servicios de pruebas: Llavero y ajustes en memoria, proveedor falso, nutrición en memoria.
struct MealTestEnvironment: Sendable {
    let services: MealAssistantServices
    let store: InMemoryMealNutritionStore
    let provider: FakeLLMProvider
    let model: LLMModel

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func make(
        provider: FakeLLMProvider = FakeLLMProvider(),
        imageSupport: ImageSupport = .confirmed,
        configured: Bool = true
    ) async throws -> MealTestEnvironment {
        let items = Dictionary(uniqueKeysWithValues: LLMProviderID.allCases.map { ($0, InMemorySecretItem()) })
        let keys = LLMKeyStore(itemFor: { items[$0]! })
        let defaults = UserDefaults(suiteName: "meal-tests-\(UUID().uuidString)")!
        let settings = LLMSettingsStore(defaults: defaults)
        let model = LLMModel(id: "claude-haiku-5-5", provider: .anthropic, displayName: "Haiku", imageSupport: imageSupport)
        if configured {
            try await keys.save(LLMFixtures.testKey, for: .anthropic)
            settings.setSelectedProvider(.anthropic)
            settings.setSelectedModel(model)
        }
        let store = InMemoryMealNutritionStore()
        let services = MealAssistantServices(nutrition: store, keys: keys, settings: settings, makeProvider: { _ in provider })
        return MealTestEnvironment(services: services, store: store, provider: provider, model: model)
    }

    @MainActor
    func viewModel(editing: DiaryEvent? = nil, ids: IDSequence = IDSequence()) -> MealAnalysisViewModel {
        MealAnalysisViewModel(
            services: services, editing: editing, at: Self.now, calendar: Self.calendar,
            now: { Self.now }, newID: { ids.next() })
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }
}
