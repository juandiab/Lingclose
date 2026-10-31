/// Un extremo de una tendencia corporal: día local (`YYYY-MM-DD`) y valor con un decimal (T-33).
struct BodyTrendPoint: Sendable, Hashable, Codable {
    var day: String
    var value: Double
}
