/// Recomendación de LingoScan para un modelo, siempre con su motivo.
enum ModelRecommendation: Sendable, Hashable, Codable {
    case recommended(reason: String)
    case notRecommended(reason: String)
    case unknown
}
