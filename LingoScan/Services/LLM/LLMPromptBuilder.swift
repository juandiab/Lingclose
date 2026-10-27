import Foundation

/// Instrucciones al modelo (mismo texto para todos los proveedores, `docs/T-21.md` §2) y el esquema de
/// la respuesta, en texto literal y como JSON Schema estricto para la salida estructurada.
enum LLMPromptBuilder {
    static let toolName = "record_food_analysis"
    static let schemaName = "food_analysis"

    /// Esquema de §2, literal.
    static let jsonSchemaLiteral = """
    {
      "kind": "food | nutrition_label | not_food",
      "name": "string | null",
      "basis": { "type": "per_100g | per_100ml | per_serving | estimated_serving", "description": "string | null", "grams": "number | null" },
      "nutrients": { "kcal": "number | null", "carbs_g": "number | null", "protein_g": "number | null", "fat_g": "number | null" },
      "confidence": "number 0–1 | null",
      "assumptions": "string | null (breve)",
      "unreadable": ["nombres de campos ilegibles de la etiqueta"]
    }
    """

    static func systemPrompt(locale: String) -> String {
        """
        Eres un asistente de registro de comidas. Recibes una foto y/o una descripción y devuelves una propuesta de nutrientes que la persona revisará y podrá corregir antes de guardar.

        Reglas:
        1. Decide tú el tipo ("kind") sin que la persona lo diga: "food" si es comida o bebida preparada, "nutrition_label" si es una tabla o etiqueta nutricional, "not_food" si no hay comida ni etiqueta.
        2. Comida ("food"): propón SIEMPRE una porción base concreta, aunque no se indique cantidad: basis.type = "estimated_serving", con basis.description (p. ej. "1 arepa mediana") y basis.grams aproximados. Estima kcal, carbs_g, protein_g y fat_g para esa porción.
        3. Etiqueta ("nutrition_label"): copia la base que se lee en la etiqueta: "per_100g", "per_100ml" o "per_serving" (con basis.description de la porción declarada y basis.grams si se lee). Copia solo los valores legibles. Lo ilegible va en null y su nombre de campo (kcal, carbs_g, protein_g o fat_g) en "unreadable". No confundas la base de la etiqueta con lo que se consumió.
        4. Nunca inventes cifras. Desconocido es null, nunca 0. Un 0 solo si la etiqueta dice 0.
        5. "not_food": basis null y todos los nutrientes null.
        6. "confidence" entre 0 y 1. "assumptions": una o dos frases breves con los supuestos (tamaño, preparación, campos ilegibles).
        7. Escribe "name" y "assumptions" en el idioma del locale \(locale).
        8. Responde solo con el JSON, sin texto alrededor, con esta forma exacta:
        \(jsonSchemaLiteral)
        """
    }

    /// Texto del mensaje del usuario. Solo la descripción que escribió la persona.
    static func userText(description: String?, hasImage: Bool) -> String {
        switch (description, hasImage) {
        case (let d?, true): "Analiza la foto. Descripción de la persona: \(d)"
        case (let d?, false): "No hay foto. Analiza esta descripción: \(d)"
        case (nil, _): "Analiza la foto."
        }
    }

    /// JSON Schema estricto (todas las claves requeridas, sin propiedades extra, nulos con `null`).
    static func strictSchema() -> [String: Any] {
        let nullableNumber: [String: Any] = ["type": ["number", "null"]]
        let nullableString: [String: Any] = ["type": ["string", "null"]]
        let basis: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["type", "description", "grams"],
            "properties": [
                "type": ["type": "string", "enum": ["per_100g", "per_100ml", "per_serving", "estimated_serving"]],
                "description": nullableString,
                "grams": nullableNumber,
            ] as [String: Any],
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["kind", "name", "basis", "nutrients", "confidence", "assumptions", "unreadable"],
            "properties": [
                "kind": ["type": "string", "enum": ["food", "nutrition_label", "not_food"]],
                "name": nullableString,
                "basis": ["anyOf": [basis, ["type": "null"]]],
                "nutrients": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["kcal", "carbs_g", "protein_g", "fat_g"],
                    "properties": ["kcal": nullableNumber, "carbs_g": nullableNumber,
                                   "protein_g": nullableNumber, "fat_g": nullableNumber],
                ] as [String: Any],
                "confidence": nullableNumber,
                "assumptions": nullableString,
                "unreadable": ["type": "array", "items": ["type": "string"]],
            ] as [String: Any],
        ]
    }
}
