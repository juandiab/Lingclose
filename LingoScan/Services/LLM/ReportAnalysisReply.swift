/// Respuesta validada del análisis de un reporte (T-27d): panorama general, una sección por reporte con datos,
/// salvedades y preguntas para explorar. Es una guía analítica de bienestar, nunca un diagnóstico.
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

    var overview: String
    var sections: [Section]
    var caveats: [String]
    var questionsToExplore: [String]

    enum CodingKeys: String, CodingKey {
        case overview, sections, caveats
        case questionsToExplore = "questions_to_explore"
    }

    /// Todo el texto visible, para validarlo de una vez.
    var allTexts: [String] {
        [overview] + sections.flatMap { [$0.title, $0.whatTheDataShows, $0.whyItMayHappen, $0.whatToTry, $0.whatToWatch] }
            + caveats + questionsToExplore
    }
}
