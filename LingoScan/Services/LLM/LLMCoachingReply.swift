/// Respuesta validada del asistente a "Preguntar al asistente" (T-25), ya acotada por `CoachingReplyParser`:
/// resumen de ≤ 280 caracteres, hasta 3 sugerencias (cuerpo de ≤ 160) y una precaución opcional.
struct LLMCoachingReply: Sendable, Equatable {
    struct Suggestion: Sendable, Equatable, Hashable {
        var title: String
        var body: String
    }

    var summary: String
    var suggestions: [Suggestion]
    var caution: String?
}
