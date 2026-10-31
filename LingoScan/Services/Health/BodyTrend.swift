/// Tendencia de una medida corporal dentro del período (T-33): solo el primer y el último valor, nunca la serie.
struct BodyTrend: Sendable, Hashable, Codable {
    /// `weight_kg`, `body_fat_pct` o `lean_mass_kg`.
    var metric: String
    var first: BodyTrendPoint
    var last: BodyTrendPoint
}
