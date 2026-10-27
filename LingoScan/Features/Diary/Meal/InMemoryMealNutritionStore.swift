import LingoCore

/// Nutrición de comidas en memoria: pruebas y previsualización. Conserva todas las versiones guardadas.
actor InMemoryMealNutritionStore: MealNutritionStore {
    private var records: [String: MealNutritionRecord] = [:]
    private(set) var savedEvents: [DiaryEvent] = []
    private(set) var savedRecords: [MealNutritionRecord] = []
    private var failNextSave = false

    init(records: [MealNutritionRecord] = []) {
        for record in records { self.records[record.eventID] = record }
    }

    func mealNutrition(eventID: String) async throws -> MealNutritionRecord? {
        records[eventID]
    }

    func saveMeal(event: DiaryEvent, nutrition: MealNutritionRecord) async throws -> EventUpsertOutcome {
        if failNextSave {
            failNextSave = false
            throw InMemoryMealNutritionStoreError.simulatedFailure
        }
        guard event.eventID == nutrition.eventID, event.kind == .meal else {
            throw InMemoryMealNutritionStoreError.mismatchedEvent
        }
        var stored = event
        stored.carbsG = nutrition.effectiveNutrients.carbsG
        let isFirst = !savedEvents.contains { $0.eventID == event.eventID }
        savedEvents.append(stored)
        savedRecords.append(nutrition)
        records[nutrition.eventID] = nutrition
        return isFirst ? .inserted : .tookDescendant
    }

    func setFailNextSave(_ value: Bool) { failNextSave = value }
}

enum InMemoryMealNutritionStoreError: Error {
    case simulatedFailure
    case mismatchedEvent
}
