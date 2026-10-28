/// Respuesta validada del modelo a "Sugerir rango": ya acotada por `RangeSuggestionBounds`.
struct LLMRangeReply: Sendable, Equatable {
    var low: Int
    var high: Int
    var explanation: String
}
