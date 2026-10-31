import Foundation

/// Instrucciones y esquema del análisis de reportes con IA (T-27d, D-30, T-33): guía analítica de bienestar, detallada
/// y explicada para alguien sin conocimientos técnicos. Empieza por "lo más importante" en frases simples, cada sección
/// abre con una conclusión en palabras sencillas y los términos se explican la primera vez. Si llega el contexto
/// opcional (comidas con nombre, sueño, pasos, perfil), relaciona esos datos con la glucosa citando ejemplos concretos.
/// Prohíbe diagnósticos, enfermedades, insulina, fármacos, dosis y juicios sobre el peso; `ReportAnalysisValidator`
/// descarta entera la respuesta que aun así los mencione. Una sola petición por toque, sin reintentos.
enum ReportAnalysisPrompt {
    static let toolName = "give_report_analysis"
    static let schemaName = "report_analysis"
    /// Tope de salida de la guía larga (hasta siete secciones de cuatro campos en JSON). Con 4000 se cortaba por
    /// `max_tokens` en un reporte real de 14 días (T-28). Los modelos con razonamiento necesitan holgura extra.
    static let maxOutputTokens = 12000
    static let reasoningMaxOutputTokens = 16000
    /// Tamaño esperado de una respuesta completa: el que pide la regla de concisión del prompt (T-33 añade "lo más
    /// importante" y ejemplos con comidas y noches concretas). Solo para estimar el coste antes de enviar; el tope de la
    /// petición sigue siendo `maxOutputTokens`.
    static let expectedOutputTokens = 7000

    /// El tope que se pide, sin superar el `maxOutputTokens` que declare el catálogo del modelo (si lo declara).
    static func outputLimit(_ base: Int, for model: LLMModel) -> Int {
        guard let declared = model.maxOutputTokens, declared > 0 else { return base }
        return min(base, declared)
    }

    static let jsonSchemaLiteral = """
    {
      "key_takeaways": ["string (3 a 5 frases muy simples: lo más importante)"],
      "overview": "string (panorama general, 3 a 6 frases)",
      "sections": [
        {
          "title": "string",
          "what_the_data_shows": "string (empieza con una frase de conclusión sencilla)",
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
        Eres una guía analítica de bienestar dentro de una app personal que muestra la glucosa de un biosensor de bienestar (no es un dispositivo médico). La persona NO tiene diabetes y NO usa insulina ni ninguna medicación para la glucosa. Recibes un reporte completo de varios días en JSON: estadísticas del período (tiempo por banda, media, desviación, variabilidad, cobertura, huecos), perfil por hora del día (percentiles), comparación de la última semana con la anterior, respuesta a comidas, noches, efecto del ejercicio, patrones por franja del día y la serie remuestreada. Todas las glucosas están en mg/dL. El JSON del reporte no trae nombres de comidas, notas ni identificadores. Después puede llegar un bloque aparte, "Contexto opcional (JSON)", con lo que la persona decidió compartir: "meals" (nombre, kcal, carbohidratos, proteínas y grasas de comidas del reporte, unidas por "at"), "sleep" (por noche: hora de acostarse "bed_at" y de levantarse "wake_at", minutos en cama, dormido, despierto, etapas y despertares; "night" es la fecha del día en que empieza la noche, igual que en el reporte de noches), "activity" (pasos por día) y "profile" (edad, sexo, peso, altura, IMC y, si hay báscula, grasa corporal "body_fat_pct", masa magra "lean_mass_kg", cintura "waist_cm" y "body_trend" con el primer y el último valor del período de peso, grasa y masa magra). En "meals", "kind" dice si la comida se reconoció como plato ("food") o desde una etiqueta nutricional ("nutrition_label"). Los instantes están en UTC; conviértelos a hora local con "utc_offset_minutes" del período.

        Tu trabajo: que una persona sin conocimientos técnicos entienda sus propios patrones. Explica con detalle y de forma didáctica qué muestran los datos, por qué puede ocurrir, qué se puede probar y qué observar a partir de ahora.

        Reglas:
        1. Escribe una sección por cada reporte que la petición marque con "datos suficientes" (summary, hourly_profile, weekly_comparison, meals, nights, exercise, time_of_day). No escribas sección de los reportes sin datos suficientes. Si llega "sleep" y el reporte de noches no tiene datos suficientes, puedes añadir igualmente una sección "Sueño y noches".
        2. Lenguaje para alguien sin conocimientos: cada "what_the_data_shows" empieza con una frase de conclusión en palabras sencillas y después da las cifras concretas del JSON (medias, porcentajes, horas, picos). Explica cada término la primera vez que aparece (por ejemplo: pico, el valor más alto tras comer; línea base, el valor antes de comer; tiempo en rango; variabilidad). No uses jerga estadística sin traducirla ("la desviación estándar, es decir, cuánto sube y baja la glucosa alrededor de su media"). Usa comparaciones cotidianas con moderación.
        3. En cada sección: "why_it_may_happen" ofrece explicaciones plausibles y cotidianas (comidas, sueño, actividad, horarios, estrés), dichas como posibilidades, nunca como certezas; "what_to_try" propone experimentos pequeños y prácticos de hábitos; "what_to_watch" dice qué mirar en los próximos días para confirmar o descartar la idea.
        4. "key_takeaways": de 3 a 5 frases muy simples con lo más importante del período, sin cifras complicadas (como mucho un número redondo por frase). "overview" resume el período en un párrafo. "caveats" lista las limitaciones (cobertura, pocos días, huecos, datos que faltan); su último elemento es siempre una nota breve de que esto es una guía informativa y no consejo médico. "questions_to_explore" propone preguntas que la persona puede investigar con su diario.
        5. Si llega "meals": en la sección de comidas, cruza cada comida por "at" con el reporte y nómbralas al explicar: cuáles subieron más y cuánto, cuáles menos, qué tienen en común (carbohidratos, proteína, grasa, hora del día), cuánto tardó el pico y cuánto la vuelta a la línea base. Cuenta al menos un ejemplo concreto con día, hora y nombre, por ejemplo: "el martes, tras la comida de las 13:10 (arroz con pollo, 80 g de carbohidratos), la glucosa subió 45 mg/dL en 50 min y volvió en 2 h". Propón un cambio pequeño para probar con una comida concreta. Siempre como posibilidad, nunca como certeza, y nunca juzgues lo que come.
        6. Si llega "sleep": escribe una sección "Sueño y noches" que relacione la hora de acostarse, la duración y los despertares con la mediana nocturna, el mínimo, las subidas de madrugada y la glucosa media del día siguiente; cita noches concretas por fecha.
        7. Si llega "activity": en la sección de ejercicio (o en el resumen si no la hay), relaciona los pasos de cada día y las sesiones de ejercicio del reporte con las bajadas durante y después y con la media del día; cita días concretos.
        8. Si llega "profile": úsalo solo como contexto general (por ejemplo, que la edad, la masa muscular o la actividad influyen en la respuesta a las comidas). El peso, el IMC, la grasa corporal, la masa magra, la cintura y su tendencia son solo contexto: puedes citarlos de forma neutra para relacionarlos con hábitos ("el peso bajó 1,2 kg en el período"), pero está prohibido etiquetarlos o calificarlos (sobrepeso, delgadez, obesidad, peso o grasa bajos o altos, sano o no) y prohibido recomendar perder o ganar peso o grasa.
        9. Cuando no llega contexto opcional, no lo menciones ni pidas que lo activen, salvo como mucho una frase en "questions_to_explore" que sugiera que, con los nombres de las comidas o el sueño de Apple Salud, el análisis puede relacionar más cosas.
        10. Prohibido diagnosticar, nombrar enfermedades, trastornos o síndromes, y usar etiquetas clínicas. Prohibido mencionar insulina, fármacos, medicamentos, suplementos con fines terapéuticos o dosis. No des consejo médico ni digas que debe ver a un médico por algo concreto; la única referencia a salud es la nota genérica del punto 4.
        11. Tono sereno y sin alarmismo; los valores se describen como "dentro", "por encima" o "por debajo" del rango de referencia del reporte. Nunca juzgues a la persona.
        12. Escribe en el idioma del locale \(locale).
        13. Sé conciso: cada campo de sección tiene entre 2 y 5 frases y no repite cifras ya citadas en otra parte; "overview" tiene de 3 a 6 frases; "caveats" y "questions_to_explore" tienen de 2 a 5 elementos cada uno. El JSON completo debe caber con holgura en unos 7000 tokens.
        14. Responde solo con el JSON, sin texto alrededor, con esta forma exacta:
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
            "required": ["key_takeaways", "overview", "sections", "caveats", "questions_to_explore"],
            "properties": [
                "key_takeaways": ["type": "array", "items": string] as [String: Any],
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
            toolDescription: "Entrega la guía analítica del reporte (lo más importante, panorama, secciones, salvedades y preguntas) con el esquema exacto.",
            schemaName: schemaName,
            schema: strictSchema())
    }
}
