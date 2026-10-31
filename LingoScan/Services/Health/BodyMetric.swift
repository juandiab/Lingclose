/// Medida corporal estándar de Apple Salud que una báscula puede escribir (T-33, adenda 1). HealthKit no tiene tipos
/// para agua, músculo, hueso ni grasa visceral: solo estos.
enum BodyMetric: String, CaseIterable, Sendable, Hashable, Codable {
    case weight = "weight_kg"
    case bodyFat = "body_fat_pct"
    case leanMass = "lean_mass_kg"
    case bmi
    case waist = "waist_cm"

    /// Métricas con tendencia (primer y último valor del período).
    static let trended: [BodyMetric] = [.weight, .bodyFat, .leanMass]
}
