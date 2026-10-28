/// Respuesta del asistente lista para mostrar: el contenido validado y de dónde viene.
struct CoachingAnswer: Sendable, Equatable {
    var reply: LLMCoachingReply
    /// "Anthropic (Claude) · claude-haiku-5-5" o "Vista previa sintética".
    var source: String
}
