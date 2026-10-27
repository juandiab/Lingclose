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
}
