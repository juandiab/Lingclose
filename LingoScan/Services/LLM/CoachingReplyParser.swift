import Foundation
import LingoCore

/// Convierte la respuesta estructurada del asistente en `LLMCoachingReply` (T-25). Rechaza con
/// `LLMError.invalidResponse` lo que no cumpla el contrato (sin resumen, sugerencias mal formadas) y **toda** respuesta
/// que mencione insulina, medicación, fármacos o dosis, aunque el resto sea válido. Los textos demasiado largos se
/// acortan a los límites (280 / 60 / 160) y sobran las sugerencias a partir de la tercera: así una respuesta pagada
/// pero algo larga no se pierde. Nunca se reintenta.
enum CoachingReplyParser {
    /// Raíces prohibidas, comparadas sin mayúsculas ni tildes.
    static let forbiddenTerms = [
        "insulin", "medicacion", "medicament", "medication", "medicine", "farmaco", "pharmac", "metformin",
        "dosis", "dosage", "pastilla",
    ]

    static func parse(text: String) throws -> LLMCoachingReply {
        guard let objectText = FoodAnalysisParser.firstJSONObject(in: text),
              let object = try? JSONSerialization.jsonObject(with: Data(objectText.utf8)) as? [String: Any] else {
            throw LLMError.invalidResponse(String(localized: "coaching.parse.noJSON", defaultValue: "la respuesta no contiene un objeto JSON"))
        }
        return try parse(object: object)
    }

    static func parse(object: [String: Any]) throws -> LLMCoachingReply {
        guard let summary = clean(object["summary"]) else {
            throw LLMError.invalidResponse(String(localized: "coaching.parse.noSummary", defaultValue: "falta el resumen"))
        }
        guard let rawSuggestions = object["suggestions"] as? [Any] else {
            throw LLMError.invalidResponse(String(localized: "coaching.parse.noSuggestions", defaultValue: "faltan las sugerencias"))
        }
        let suggestions = try rawSuggestions.map { raw -> LLMCoachingReply.Suggestion in
            guard let item = raw as? [String: Any], let title = clean(item["title"]), let body = clean(item["body"]) else {
                throw LLMError.invalidResponse(String(localized: "coaching.parse.badSuggestion", defaultValue: "sugerencia sin título o sin texto"))
            }
            return LLMCoachingReply.Suggestion(title: title, body: body)
        }
        // Se mira el texto completo, antes de acortarlo, para que un término no se escape por el recorte.
        let full = LLMCoachingReply(summary: summary, suggestions: suggestions, caution: clean(object["caution"]))
        if let term = forbiddenTerm(in: full) {
            throw LLMError.invalidResponse(String(localized: "coaching.parse.forbidden",
                                                  defaultValue: "la respuesta habla de medicación (\(term)) y se descartó"))
        }
        return LLMCoachingReply(
            summary: shorten(full.summary, to: CoachingPrompt.maxSummary),
            suggestions: full.suggestions.prefix(CoachingPrompt.maxSuggestions).map {
                .init(title: shorten($0.title, to: CoachingPrompt.maxTitle), body: shorten($0.body, to: CoachingPrompt.maxBody))
            },
            caution: full.caution.map { shorten($0, to: CoachingPrompt.maxSummary) })
    }

    /// Primera raíz prohibida que aparezca en cualquier texto de la respuesta.
    static func forbiddenTerm(in reply: LLMCoachingReply) -> String? {
        let texts = [reply.summary, reply.caution ?? ""] + reply.suggestions.flatMap { [$0.title, $0.body] }
        let haystack = texts.joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return forbiddenTerms.first { haystack.contains($0) }
    }

    private static func clean(_ raw: Any?) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Acorta a `limit` caracteres (con "…") por el último espacio si lo hay.
    static func shorten(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = String(text.prefix(limit - 1))
        var trimmed = Substring(cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut)
        let tail = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        while let last = trimmed.unicodeScalars.last, tail.contains(last) { trimmed = trimmed.dropLast() }
        return trimmed + "…"
    }
}
