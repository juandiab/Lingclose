import LingoCore

/// Nutrición inventada para las comidas sintéticas de la previsualización (T-33): un nombre y unos nutrientes fijos por
/// evento `synthetic-…`, para ver en el simulador cómo cambia "Qué se enviará" con "Comidas con nombre". Los
/// carbohidratos se dejan desconocidos (los del evento ya van en el snapshot). No guarda nada.
struct PreviewMealNutritionStore: MealNutritionStore {
    private static let menu: [(name: String, kcal: Double, protein: Double, fat: Double)] = [
        ("Arroz con pollo y ensalada", 640, 32, 18), ("Avena con banano", 380, 12, 8),
        ("Arepa con queso y huevo", 520, 24, 22), ("Pasta con tomate", 610, 19, 14),
        ("Lentejas con arroz", 560, 26, 9), ("Sándwich de pavo", 450, 28, 15),
    ]

    func mealNutrition(eventID: String) async throws -> MealNutritionRecord? {
        guard eventID.hasPrefix("synthetic") else { return nil }
        let item = Self.menu[eventID.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.menu.count]
        return MealNutritionRecord(
            eventID: eventID, source: .manual, kind: .food, name: item.name,
            basis: .estimatedServing(description: nil, grams: nil),
            baseNutrients: Nutrients(kcal: item.kcal, carbsG: nil, proteinG: item.protein, fatG: item.fat),
            updatedAt: UTCInstant(epochSeconds: 0))
    }

    func saveMeal(event: DiaryEvent, nutrition: MealNutritionRecord) async throws -> EventUpsertOutcome {
        throw InMemoryMealNutritionStoreError.mismatchedEvent
    }
}
