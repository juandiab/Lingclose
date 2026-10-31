/// Perfil y composición corporal de Apple Salud para el análisis (T-33 y adenda 1): solo contexto; la IA nunca lo
/// etiqueta ni lo juzga. Cada medida es la más reciente dentro del período o anterior, con un decimal; lo que no hay
/// no se envía. `body_trend` da para peso, grasa y masa magra el primer y el último valor del período (sin series).
struct ReportAnalysisProfileContext: Sendable, Hashable, Codable {
    var ageYears: Int?
    /// `female`, `male` u `other`.
    var sex: String?
    var weightKg: Double?
    var heightCm: Double?
    /// Índice de masa corporal: el de Salud si existe; si no, el calculado con peso y altura.
    var bmi: Double?
    var bodyFatPct: Double?
    var leanMassKg: Double?
    var waistCm: Double?
    var bodyTrend: [BodyTrend]?

    var isEmpty: Bool {
        ageYears == nil && sex == nil && weightKg == nil && heightCm == nil && bmi == nil && bodyFatPct == nil
            && leanMassKg == nil && waistCm == nil && bodyTrend == nil
    }

    enum CodingKeys: String, CodingKey {
        case ageYears = "age_years"
        case sex
        case weightKg = "weight_kg"
        case heightCm = "height_cm"
        case bmi
        case bodyFatPct = "body_fat_pct"
        case leanMassKg = "lean_mass_kg"
        case waistCm = "waist_cm"
        case bodyTrend = "body_trend"
    }
}
