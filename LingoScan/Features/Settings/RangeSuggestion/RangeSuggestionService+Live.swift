extension RangeSuggestionService {
    /// App real: lecturas en SQLite, perfil por HealthKit y el mismo proveedor, clave y modelo del asistente de comidas.
    static func live(readings: any RangeReadingsSource, assistant: MealAssistantServices) -> RangeSuggestionService {
        RangeSuggestionService(readings: readings, health: HealthKitProfileReader(), keys: assistant.keys,
                               settings: assistant.settings, makeProvider: assistant.makeProvider)
    }
}
