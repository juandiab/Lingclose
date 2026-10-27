import Foundation

/// Energía, proteína o grasa de una comida, listas para Health. Solo `meal` no sintética, no borrada, con
/// `MealNutritionRecord` y valor **conocido** (`effectiveNutrients`). `nil` nunca se convierte en 0; un 0
/// conocido sí se exporta. Los carbohidratos siguen saliendo del evento (`HealthCarbExportable`).
public struct HealthNutrientExportable: Sendable, Hashable {
    public let eventID: String
    public let kind: HealthSubjectKind
    public let at: UTCInstant
    /// kcal para `energyKcal`; gramos para `proteinG` y `fatG`.
    public let value: Double
    public let note: String?
    public let syncVersion: Int

    /// `<event_id>:<subject_kind>`: estable entre revisiones para que Health sustituya la muestra al editar
    /// (`HKMetadataKeySyncVersion` = `revision`). Distinto del de carbohidratos (`event_id`).
    public var syncIdentifier: String { Self.syncIdentifier(eventID: eventID, kind: kind) }

    public static func syncIdentifier(eventID: String, kind: HealthSubjectKind) -> String {
        "\(eventID):\(kind.rawValue)"
    }

    public init?(event: DiaryEvent, nutrition: MealNutritionRecord?, kind: HealthSubjectKind) {
        guard HealthSubjectKind.mealNutrients.contains(kind),
              event.kind == .meal, !event.synthetic, !event.deleted,
              let nutrition, nutrition.eventID == event.eventID
        else { return nil }
        let n = nutrition.effectiveNutrients
        let known: Double? = switch kind {
        case .energyKcal: n.kcal
        case .proteinG: n.proteinG
        case .fatG: n.fatG
        case .glucose, .carbs: nil
        }
        guard let known, known.isFinite, known >= 0 else { return nil }
        eventID = event.eventID
        self.kind = kind
        at = event.at
        value = known
        let trimmed = event.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        note = (trimmed?.isEmpty ?? true) ? nil : trimmed
        syncVersion = event.revision
    }

    /// Una por nutriente conocido, en el orden energía, proteína, grasa.
    public static func all(event: DiaryEvent, nutrition: MealNutritionRecord?) -> [HealthNutrientExportable] {
        HealthSubjectKind.mealNutrients.compactMap { HealthNutrientExportable(event: event, nutrition: nutrition, kind: $0) }
    }
}
