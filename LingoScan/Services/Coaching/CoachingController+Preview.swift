import Foundation
import LingoCore

extension CoachingController {
    /// Tarjeta de ejemplo (alta tras una comida, ya abierta) con el asistente sintético. Solo `#Preview` y
    /// `-previewCoaching YES` junto a `-previewSensorState`.
    static func preview(assistant: any CoachingAsking = PreviewCoachingAssistant()) -> CoachingController {
        let defaults = UserDefaults(suiteName: "lingoscan.coaching.preview") ?? .standard
        let store = CoachingStore(defaults: defaults)
        let context = CoachingContext(kind: .high, value: 165, slopePerMinute: 1.4, minutesSinceLastMeal: 45,
                                      lastMealCarbsG: 72, hour: 14, timeInRangeToday: 0.82)
        store.save(CoachingRecord(
            id: "lingoscan.alert.preview", context: context, tipIDs: CoachingRules.tips(for: context).map(\.id),
            mealNutrients: Nutrients(kcal: 640, carbsG: 72, proteinG: 24, fatG: 21), exerciseKind: nil,
            exerciseDurationMin: nil, createdAt: .now.addingTimeInterval(-300), openedAt: .now))
        return CoachingController(store: store, assistant: assistant)
    }
}
