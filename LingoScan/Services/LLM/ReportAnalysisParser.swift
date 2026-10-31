import Foundation
import LingoCore

/// Convierte la respuesta estructurada del análisis en `ReportAnalysisReply`. Solo comprueba la **forma**: lo que
/// no cumpla el contrato (sin resumen, sin secciones, JSON truncado) es `LLMError.invalidResponse` y el análisis
/// queda `failed`. El contenido (diagnóstico, insulina, medicación) lo juzga `ReportAnalysisValidator`, que lo
/// deja `rejected`. Nunca se reintenta.
enum ReportAnalysisParser {
    static let maxSections = 10
    static let maxListItems = 8

    static func parse(text: String) throws -> ReportAnalysisReply {
        guard let objectText = FoodAnalysisParser.firstJSONObject(in: text),
              let object = try? JSONSerialization.jsonObject(with: Data(objectText.utf8)) as? [String: Any] else {
            throw LLMError.invalidResponse(String(localized: "reports.analysis.parse.noJSON",
                                                  defaultValue: "la respuesta no contiene un objeto JSON completo"))
        }
        return try parse(object: object)
    }

    static func parse(object: [String: Any]) throws -> ReportAnalysisReply {
        guard let overview = clean(object["overview"]) else {
            throw LLMError.invalidResponse(String(localized: "reports.analysis.parse.noOverview", defaultValue: "falta el panorama general"))
        }
        guard let rawSections = object["sections"] as? [Any], !rawSections.isEmpty else {
            throw LLMError.invalidResponse(String(localized: "reports.analysis.parse.noSections", defaultValue: "faltan las secciones"))
        }
        let sections = try rawSections.prefix(maxSections).map { raw -> ReportAnalysisReply.Section in
            guard let item = raw as? [String: Any], let title = clean(item["title"]),
                  let shows = clean(item["what_the_data_shows"]) else {
                throw LLMError.invalidResponse(String(localized: "reports.analysis.parse.badSection",
                                                      defaultValue: "sección sin título o sin descripción de los datos"))
            }
            return ReportAnalysisReply.Section(
                title: title, whatTheDataShows: shows,
                whyItMayHappen: clean(item["why_it_may_happen"]) ?? "",
                whatToTry: clean(item["what_to_try"]) ?? "",
                whatToWatch: clean(item["what_to_watch"]) ?? "")
        }
        return ReportAnalysisReply(overview: overview, sections: sections,
                                   caveats: strings(object["caveats"]), questionsToExplore: strings(object["questions_to_explore"]))
    }

    private static func strings(_ raw: Any?) -> [String] {
        ((raw as? [Any]) ?? []).compactMap(clean).prefix(maxListItems).map { $0 }
    }

    private static func clean(_ raw: Any?) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
