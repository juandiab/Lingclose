/// Precio publicado de un modelo, en dólares por millón de tokens. Siempre con su fuente y fecha:
/// un precio sin fuente no se muestra (la UI pone "No publicado" cuando `LLMModel.pricing` es `nil`).
struct ModelPricing: Sendable, Hashable, Codable {
    var inputUSDPerMTok: Double?
    var outputUSDPerMTok: Double?
    /// URL de la página de precios o "catálogo de OpenRouter". Obligatorio si hay precio.
    var source: String
    /// Mes de la consulta, p. ej. "2026-10".
    var asOf: String
}
