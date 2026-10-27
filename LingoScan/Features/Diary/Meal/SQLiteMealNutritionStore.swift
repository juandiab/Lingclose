import LingoCore

/// Nutrición de comidas sobre `SQLiteStore`: `saveMeal` escribe evento y fila en una transacción.
struct SQLiteMealNutritionStore: MealNutritionStore {
    let store: SQLiteStore

    func mealNutrition(eventID: String) async throws -> MealNutritionRecord? {
        try await store.mealNutrition(eventID: eventID)
    }

    func saveMeal(event: DiaryEvent, nutrition: MealNutritionRecord) async throws -> EventUpsertOutcome {
        try await store.saveMeal(event: event, nutrition: nutrition)
    }
}
