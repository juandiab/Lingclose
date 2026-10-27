import LingoCore

/// Lo que la pantalla de comidas necesita de la base: leer la nutrición de un evento y guardar evento y
/// nutrición juntos (una transacción en la implementación real).
protocol MealNutritionStore: Sendable {
    /// Registro de nutrición del evento, o `nil` si no tiene (eventos `meal` antiguos o sin análisis).
    func mealNutrition(eventID: String) async throws -> MealNutritionRecord?
    /// Guarda el evento `meal` y su nutrición. Cada guardado lleva un `edit_id` nuevo.
    func saveMeal(event: DiaryEvent, nutrition: MealNutritionRecord) async throws -> EventUpsertOutcome
}
