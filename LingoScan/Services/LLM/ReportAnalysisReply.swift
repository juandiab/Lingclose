/// Respuesta validada del análisis de un reporte (T-27d, T-33): lo más importante en frases simples, panorama general,
/// una sección por reporte con datos, salvedades y preguntas para explorar. Es una guía analítica de bienestar, nunca
/// un diagnóstico. Los análisis guardados antes de T-33 no traen `key_takeaways`: se leen con la lista vacía.
struct ReportAnalysisReply: Sendable, Hashable, Codable {
    struct Section: Sendable, Hashable, Codable {
        var title: String
        var whatTheDataShows: String
        var whyItMayHappen: String
        var whatToTry: String
        var whatToWatch: String

        enum CodingKeys: String, CodingKey {
            case title
            case whatTheDataShows = "what_the_data_shows"
            case whyItMayHappen = "why_it_may_happen"
            case whatToTry = "what_to_try"
            case whatToWatch = "what_to_watch"
        }
    }

    /// "Lo más importante": 3 a 5 frases muy simples. Vacío en análisis anteriores a T-33.
    var keyTakeaways: [String]
    var overview: String
    var sections: [Section]
    var caveats: [String]
    var questionsToExplore: [String]

    init(keyTakeaways: [String] = [], overview: String, sections: [Section], caveats: [String], questionsToExplore: [String]) {
        self.keyTakeaways = keyTakeaways
        self.overview = overview
        self.sections = sections
        self.caveats = caveats
        self.questionsToExplore = questionsToExplore
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyTakeaways = try c.decodeIfPresent([String].self, forKey: .keyTakeaways) ?? []
        overview = try c.decode(String.self, forKey: .overview)
        sections = try c.decode([Section].self, forKey: .sections)
        caveats = try c.decode([String].self, forKey: .caveats)
        questionsToExplore = try c.decode([String].self, forKey: .questionsToExplore)
    }

    enum CodingKeys: String, CodingKey {
        case keyTakeaways = "key_takeaways"
        case overview, sections, caveats
        case questionsToExplore = "questions_to_explore"
    }

    /// Todo el texto visible, para validarlo de una vez.
    var allTexts: [String] {
        keyTakeaways + [overview]
            + sections.flatMap { [$0.title, $0.whatTheDataShows, $0.whyItMayHappen, $0.whatToTry, $0.whatToWatch] }
            + caveats + questionsToExplore
    }
}
