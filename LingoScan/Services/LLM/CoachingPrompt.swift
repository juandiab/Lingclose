import Foundation

/// Instrucciones y esquema de "Preguntar al asistente" (T-25): el modelo recibe solo el contexto agregado de una
/// alerta y devuelve un resumen, hasta 3 sugerencias de bienestar y una precaución opcional. El prompt exige: persona
/// sin diabetes, bienestar, nada de fármacos, insulina ni dosis, sin diagnósticos, y recomendar un profesional de la
/// salud si hay síntomas persistentes. `CoachingReplyParser` descarta la respuesta si aun así menciona insulina o
/// medicación.
enum CoachingPrompt {
    static let toolName = "give_wellbeing_suggestions"
    static let schemaName = "wellbeing_suggestions"
    static let maxSummary = 280
    static let maxSuggestions = 3
    static let maxTitle = 60
    static let maxBody = 160

    static let jsonSchemaLiteral = """
    {
      "summary": "string (≤ \(maxSummary) caracteres)",
      "suggestions": [ { "title": "string (≤ \(maxTitle))", "body": "string (≤ \(maxBody))" } ],
      "caution": "string o null"
    }
    """

    static func systemPrompt(locale: String) -> String {
        """
        Eres un asistente de bienestar dentro de una app personal que muestra la glucosa de un biosensor de bienestar (no es un dispositivo médico). La persona NO tiene diabetes y NO usa insulina ni ninguna medicación para la glucosa. Acaba de recibir una alerta informativa (alta, baja, subida rápida, bajada rápida o sin datos). Recibes solo un contexto agregado: tipo de alerta, valor y pendiente, hora local, tiempo en rango del día, minutos desde la última comida y sus nutrientes, minutos desde el último ejercicio y su tipo, y los consejos que la app ya mostró.

        Reglas:
        1. Da hasta \(maxSuggestions) sugerencias prácticas de bienestar para las próximas horas (moverse, hidratarse, qué comer o evitar ahora, descanso, esperar y volver a mirar). Cada una con un título corto (≤ \(maxTitle) caracteres) y una frase (≤ \(maxBody) caracteres).
        2. No repitas los consejos de "tips_already_shown"; complétalos.
        3. Prohibido mencionar insulina, fármacos, medicamentos, suplementos con fines terapéuticos o dosis. No diagnostiques ni nombres enfermedades. No des consejo médico.
        4. Si el contexto sugiere síntomas o la situación se repite, di en "caution" que consulte a un profesional de la salud si los síntomas persisten. Si no hace falta, "caution" es null.
        5. "summary" (≤ \(maxSummary) caracteres) explica en lenguaje llano qué puede estar pasando, sin alarmismo y recordando que es informativo.
        6. Escribe en el idioma del locale \(locale).
        7. Responde solo con el JSON, sin texto alrededor, con esta forma exacta:
        \(jsonSchemaLiteral)
        """
    }

    static func strictSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["summary", "suggestions", "caution"],
            "properties": [
                "summary": ["type": "string"],
                "suggestions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["title", "body"],
                        "properties": ["title": ["type": "string"], "body": ["type": "string"]] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
                "caution": ["type": ["string", "null"]],
            ] as [String: Any],
        ]
    }

    static func prompt(for request: CoachingRequest) -> StructuredPrompt {
        StructuredPrompt(
            system: systemPrompt(locale: request.locale),
            userText: request.userText,
            toolName: toolName,
            toolDescription: "Entrega el resumen, las sugerencias de bienestar y la precaución, con el esquema exacto.",
            schemaName: schemaName,
            schema: strictSchema())
    }
}
