import Foundation

/// Instrucciones y esquema de "Sugerir rango": el modelo recibe solo agregados y devuelve un rango
/// acotado con una explicación breve. El prompt le exige decir que edad, peso y altura no determinan un
/// rango de glucosa validado y que la personalización sale de las lecturas propias.
enum RangeSuggestionPrompt {
    static let toolName = "propose_reference_range"
    static let schemaName = "reference_range"

    static let jsonSchemaLiteral = """
    {
      "low_mgdl": "entero entre \(RangeSuggestionBounds.low.lowerBound) y \(RangeSuggestionBounds.low.upperBound)",
      "high_mgdl": "entero entre \(RangeSuggestionBounds.high.lowerBound) y \(RangeSuggestionBounds.high.upperBound), al menos \(RangeSuggestionBounds.minimumGap) por encima de low_mgdl",
      "explanation": "string (2 a 4 frases)"
    }
    """

    static func systemPrompt(locale: String) -> String {
        """
        Eres un asistente de una app personal de bienestar que muestra la glucosa de un biosensor con dos líneas de referencia (baja y alta, en mg/dL) para leer la curva. No es una app médica y la persona no usa insulina. Recibes solo cifras agregadas de sus propias lecturas de los últimos días (percentiles 5 y 95, mediana, media, desviación, horas cubiertas), una propuesta estadística ya calculada con los percentiles 5 y 95 y, si existen, edad, sexo biológico e IMC. Nunca recibes lecturas individuales.

        Reglas:
        1. Propón una línea baja y una línea alta para leer la curva, partiendo de la propuesta estadística. Solo apártate de ella con un motivo concreto que expliques (por ejemplo, redondear a múltiplos de 5, pocas horas de datos o una desviación muy alta); si no hay motivo, devuélvela tal cual.
        2. Límites obligatorios: low_mgdl entre \(RangeSuggestionBounds.low.lowerBound) y \(RangeSuggestionBounds.low.upperBound); high_mgdl entre \(RangeSuggestionBounds.high.lowerBound) y \(RangeSuggestionBounds.high.upperBound); high_mgdl ≥ low_mgdl + \(RangeSuggestionBounds.minimumGap). Ambos enteros.
        3. La edad, el sexo biológico, el peso y la altura NO determinan un rango de glucosa validado. No los uses para desplazar el rango. Di explícitamente en la explicación que la personalización sale de las lecturas propias y que esos datos del perfil no fijan un rango validado.
        4. No diagnostiques, no menciones enfermedades ni tratamientos, no des consejo médico. Las líneas son una ayuda visual para leer la curva y no son objetivos clínicos. Dilo en la explicación en una frase.
        5. Si la cobertura es escasa (menos de 72 horas), dilo y recomienda revisar el rango cuando haya más días.
        6. Escribe la explicación en el idioma del locale \(locale), en 2 a 4 frases, sin listas.
        7. Responde solo con el JSON, sin texto alrededor, con esta forma exacta:
        \(jsonSchemaLiteral)
        """
    }

    static func strictSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["low_mgdl", "high_mgdl", "explanation"],
            "properties": [
                "low_mgdl": ["type": "integer"],
                "high_mgdl": ["type": "integer"],
                "explanation": ["type": "string"],
            ] as [String: Any],
        ]
    }

    static func prompt(for request: RangeSuggestionRequest) -> StructuredPrompt {
        StructuredPrompt(
            system: systemPrompt(locale: request.locale),
            userText: request.userText,
            toolName: toolName,
            toolDescription: "Entrega el rango de referencia propuesto y su explicación, con el esquema exacto.",
            schemaName: schemaName,
            schema: strictSchema())
    }
}
