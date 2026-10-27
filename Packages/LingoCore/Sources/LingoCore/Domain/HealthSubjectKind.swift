/// `subject_kind` del ledger (contrato §5.4). `energy_kcal`, `protein_g` y `fat_g` son la propuesta draft.5:
/// como `carbs`, su `subject_id` es el `event_id` de la comida.
public enum HealthSubjectKind: String, Sendable, Codable, Hashable, CaseIterable {
    case glucose
    case carbs
    case energyKcal = "energy_kcal"
    case proteinG = "protein_g"
    case fatG = "fat_g"

    /// Energía, proteína y grasa: salen de `MealNutritionRecord.effectiveNutrients`, no del evento.
    public static let mealNutrients: [HealthSubjectKind] = [.energyKcal, .proteinG, .fatG]

    /// `true` si `subject_id` es un `event_id` (todo menos glucosa).
    public var isMealSubject: Bool { self != .glucose }
}
