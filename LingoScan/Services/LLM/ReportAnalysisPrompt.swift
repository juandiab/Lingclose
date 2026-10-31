import Foundation

/// Instrucciones y esquema del análisis de reportes con IA (T-27d, D-30): guía analítica de bienestar, detallada y
/// didáctica, que explica qué muestran los datos, por qué puede ocurrir, qué probar y qué observar. Prohíbe
/// diagnósticos, enfermedades, insulina, fármacos y dosis; `ReportAnalysisValidator` descarta entera la respuesta
/// que aun así los mencione. Una sola petición por toque, sin reintentos.
enum ReportAnalysisPrompt {
    static let toolName = "give_report_analysis"
    static let schemaName = "report_analysis"
    /// Guía larga: una sección por reporte con datos. Los modelos con razonamiento necesitan holgura extra.
    static let maxOutputTokens = 4000
    static let reasoningMaxOutputTokens = 8000

    static let jsonSchemaLiteral = """
    {
      "overview": "string (panorama general, 3 a 6 frases)",
      "sections": [
        {
          "title": "string",
          "what_the_data_shows": "string",
          "why_it_may_happen": "string",
          "what_to_try": "string",
          "what_to_watch": "string"
        }
      ],
      "caveats": ["string"],
      "questions_to_explore": ["string"]
    }
    """

    static func systemPrompt(locale: String) -> String {
        """
        Eres una guía analítica de bienestar dentro de una app personal que muestra la glucosa de un biosensor de bienestar (no es un dispositivo médico). La persona NO tiene diabetes y NO usa insulina ni ninguna medicación para la glucosa. Recibes un reporte completo de varios días en JSON: estadísticas del período (tiempo por banda, media, desviación, variabilidad, cobertura, huecos), perfil por hora del día (percentiles), comparación de la última semana con la anterior, respuesta a comidas, noches, efecto del ejercicio, patrones por franja del día y la serie remuestreada. Todas las glucosas están en mg/dL. El JSON no trae nombres de comidas, notas ni identificadores.

        Tu trabajo: explicar con detalle y de forma didáctica qué muestran los datos, por qué puede ocurrir, qué se puede probar y qué observar a partir de ahora, para que la persona entienda sus propios patrones.

        Reglas:
        1. Escribe una sección por cada reporte que la petición marque con "datos suficientes" (summary, hourly_profile, weekly_comparison, meals, nights, exercise, time_of_day). No escribas sección de los reportes sin datos suficientes.
        2. En cada sección: "what_the_data_shows" cita cifras concretas del JSON (medias, porcentajes, horas, picos); "why_it_may_happen" ofrece explicaciones plausibles y cotidianas (comidas, sueño, actividad, horarios, estrés), dichas como posibilidades, nunca como certezas; "what_to_try" propone experimentos pequeños y prácticos de hábitos; "what_to_watch" dice qué mirar en los próximos días para confirmar o descartar la idea.
        3. "overview" resume lo más importante del período. "caveats" lista las limitaciones (cobertura, pocos días, huecos, datos que faltan); su último elemento es siempre una nota breve de que esto es una guía informativa y no consejo médico. "questions_to_explore" propone preguntas que la persona puede investigar con su diario.
        4. Prohibido diagnosticar, nombrar enfermedades, trastornos o síndromes, y usar etiquetas clínicas. Prohibido mencionar insulina, fármacos, medicamentos, suplementos con fines terapéuticos o dosis. No des consejo médico ni digas que debe ver a un médico por algo concreto; la única referencia a salud es la nota genérica del punto 3.
        5. Lenguaje llano, tono sereno y sin alarmismo; los valores se describen como "dentro", "por encima" o "por debajo" del rango de referencia del reporte. Nunca juzgues a la persona.
        6. Escribe en el idioma del locale \(locale).
        7. Responde solo con el JSON, sin texto alrededor, con esta forma exacta:
        \(jsonSchemaLiteral)
        """
    }

    static func strictSchema() -> [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let section: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "what_the_data_shows", "why_it_may_happen", "what_to_try", "what_to_watch"],
            "properties": [
                "title": string, "what_the_data_shows": string, "why_it_may_happen": string,
                "what_to_try": string, "what_to_watch": string,
            ] as [String: Any],
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["overview", "sections", "caveats", "questions_to_explore"],
            "properties": [
                "overview": string,
                "sections": ["type": "array", "items": section] as [String: Any],
                "caveats": ["type": "array", "items": string] as [String: Any],
                "questions_to_explore": ["type": "array", "items": string] as [String: Any],
            ] as [String: Any],
        ]
    }

    static func prompt(for request: ReportAnalysisRequest) -> StructuredPrompt {
        StructuredPrompt(
            system: systemPrompt(locale: request.locale),
            userText: request.userText,
            toolName: toolName,
            toolDescription: "Entrega la guía analítica del reporte (panorama, secciones, salvedades y preguntas) con el esquema exacto.",
            schemaName: schemaName,
            schema: strictSchema())
    }
}
