import Foundation

/// Asistente fijo y rotulado para `#Preview` y `-previewSensorState … -previewCoaching YES`: no lee claves ni red.
struct PreviewCoachingAssistant: CoachingAsking {
    var configured = true
    var result: Result<LLMCoachingReply, LLMError> = .success(PreviewCoachingAssistant.sample)
    var delay: Duration = .milliseconds(500)

    func isConfigured() async -> Bool { configured }

    func ask(_ record: CoachingRecord) async throws -> CoachingAnswer {
        try await Task.sleep(for: delay)
        return CoachingAnswer(reply: try result.get(),
                              source: String(localized: "coaching.preview.source", defaultValue: "Vista previa sintética"))
    }

    static let sample = LLMCoachingReply(
        summary: "Vista previa sintética. Subir tras una comida con bastantes carbohidratos es habitual; el pico suele bajar solo en una o dos horas.",
        suggestions: [
            .init(title: "Pausa activa", body: "Si estás sentado, levántate cada 30 minutos y camina un par de minutos."),
            .init(title: "Cena ligera", body: "Si aún no has cenado, prioriza verdura y proteína y deja el postre para otro día."),
            .init(title: "Mira la tendencia", body: "Revisa la curva en una hora: lo importante es que vuelva a tu rango."),
        ],
        caution: "Si notas síntomas que persisten, consulta a un profesional de la salud.")
}
