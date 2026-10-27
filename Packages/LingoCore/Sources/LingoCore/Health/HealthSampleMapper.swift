import Foundation

/// Comida exportable: solo `meal` no sintética, no borrada y con carbohidratos > 0. El filtro es estructural.
public struct HealthCarbExportable: Sendable, Hashable {
    public let eventID: String
    public let at: UTCInstant
    public let carbsG: Double
    public let note: String?
    public let syncVersion: Int

    public init?(event: DiaryEvent) {
        guard event.kind == .meal, !event.synthetic, !event.deleted,
              let carbs = event.carbsG, carbs > 0, carbs.isFinite
        else { return nil }
        eventID = event.eventID
        at = event.at
        carbsG = carbs
        let trimmed = event.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        note = (trimmed?.isEmpty ?? true) ? nil : trimmed
        syncVersion = event.revision
    }
}

public enum HealthSampleMapper {
    /// `syncIdentifier` permite conservar el ya usado en un intento previo (contrato §7.3).
    public static func spec(for reading: HealthExportable, syncIdentifier: String? = nil) -> HealthSampleSpec {
        HealthSampleSpec(
            kind: .glucose, value: Double(reading.valueMgdl), date: reading.measuredAt,
            syncIdentifier: syncIdentifier ?? reading.syncIdentifier, syncVersion: reading.syncVersion,
            sessionID: reading.sessionID, lifeCount: reading.lifeCount, origin: reading.origin.rawValue,
            trend: reading.trend
        )
    }

    public static func spec(for meal: HealthCarbExportable, syncIdentifier: String? = nil) -> HealthSampleSpec {
        HealthSampleSpec(
            kind: .carbs, value: meal.carbsG, date: meal.at,
            syncIdentifier: syncIdentifier ?? meal.eventID, syncVersion: meal.syncVersion, note: meal.note
        )
    }

    public static func spec(for nutrient: HealthNutrientExportable, syncIdentifier: String? = nil) -> HealthSampleSpec {
        HealthSampleSpec(
            kind: nutrient.kind, value: nutrient.value, date: nutrient.at,
            syncIdentifier: syncIdentifier ?? nutrient.syncIdentifier, syncVersion: nutrient.syncVersion, note: nutrient.note
        )
    }

    /// Todas las muestras de una comida: carbohidratos desde `event.carbsG` (como siempre) y energía, proteína y
    /// grasa desde `nutrition.effectiveNutrients`, una por valor conocido. Sin registro solo salen carbohidratos.
    public static func specs(for event: DiaryEvent, nutrition: MealNutritionRecord?) -> [HealthSampleSpec] {
        let carbs = HealthCarbExportable(event: event).map { spec(for: $0) }
        return (carbs.map { [$0] } ?? []) + HealthNutrientExportable.all(event: event, nutrition: nutrition).map { spec(for: $0) }
    }
}
