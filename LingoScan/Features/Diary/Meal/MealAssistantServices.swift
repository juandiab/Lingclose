import LingoCore

/// Todo lo que el asistente de comidas necesita: base de nutrición, claves, ajustes y proveedores.
/// Se inyecta por el entorno de SwiftUI (`\.mealAssistant`) para no cambiar las firmas de Hoy y Diario.
struct MealAssistantServices: Sendable {
    let nutrition: any MealNutritionStore
    let keys: LLMKeyStore
    let settings: LLMSettingsStore
    let makeProvider: @Sendable (LLMProviderID) -> any LLMProvider

    init(
        nutrition: any MealNutritionStore,
        keys: LLMKeyStore = LLMKeyStore(),
        settings: LLMSettingsStore = LLMSettingsStore(),
        makeProvider: @escaping @Sendable (LLMProviderID) -> any LLMProvider = { LLMProviderRegistry().provider(for: $0) }
    ) {
        self.nutrition = nutrition
        self.keys = keys
        self.settings = settings
        self.makeProvider = makeProvider
    }

    /// App real: nutrición en SQLite, claves en el Llavero, proveedores con la red real.
    static func live(store: SQLiteStore) -> MealAssistantServices {
        MealAssistantServices(nutrition: SQLiteMealNutritionStore(store: store))
    }

    /// Previsualización y valor por defecto del entorno: nutrición en memoria.
    static let preview = MealAssistantServices(nutrition: InMemoryMealNutritionStore())
}
