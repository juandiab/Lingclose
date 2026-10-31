import Foundation
import Testing
@testable import LingoScan

/// Forma de la respuesta: lo que no cumpla el contrato es `LLMError.invalidResponse`.
struct ReportAnalysisParserTests {
    @Test func validObjectRoundTripsThroughCodable() throws {
        let reply = try ReportAnalysisParser.parse(object: ReportAnalysisFixtures.replyObject())
        #expect(reply.sections.count == 2)
        let json = try #require(ReportAnalysisService.encode(reply))
        #expect(json.contains("what_the_data_shows") && json.contains("questions_to_explore"))
        #expect(ReportAnalysisService.decode(json) == reply)
    }

    @Test func textWithSurroundingProseIsAccepted() throws {
        let text = "Aquí va la guía:\n\(ReportAnalysisFixtures.replyText())\nFin."
        #expect(try ReportAnalysisParser.parse(text: text).sections.count == 2)
    }

    @Test func missingPartsAreRejected() {
        var noOverview = ReportAnalysisFixtures.replyObject()
        noOverview["overview"] = "  "
        #expect(throws: LLMError.self) { try ReportAnalysisParser.parse(object: noOverview) }
        var badSection = ReportAnalysisFixtures.replyObject()
        badSection["sections"] = [["title": "Solo título"]]
        #expect(throws: LLMError.self) { try ReportAnalysisParser.parse(object: badSection) }
        #expect(throws: LLMError.self) { try ReportAnalysisParser.parse(text: "no es json") }
    }

    @Test func optionalListsDefaultToEmptyAndAreCapped() throws {
        var object = ReportAnalysisFixtures.replyObject()
        object["caveats"] = nil
        object["questions_to_explore"] = (1...20).map { "Pregunta \($0)" }
        let reply = try ReportAnalysisParser.parse(object: object)
        #expect(reply.caveats.isEmpty)
        #expect(reply.questionsToExplore.count == ReportAnalysisParser.maxListItems)
    }

    // MARK: - T-33: "Lo más importante"

    @Test func keyTakeawaysAreParsedAndValidated() throws {
        var object = ReportAnalysisFixtures.replyObject()
        object["key_takeaways"] = ["Tu glucosa estuvo casi siempre en rango.", "  ", "Las cenas tardías suben más."]
        let reply = try ReportAnalysisParser.parse(object: object)
        #expect(reply.keyTakeaways == ["Tu glucosa estuvo casi siempre en rango.", "Las cenas tardías suben más."])
        #expect(reply.allTexts.first == "Tu glucosa estuvo casi siempre en rango.")
        let json = try #require(ReportAnalysisService.encode(reply))
        #expect(json.contains("key_takeaways"))
        #expect(ReportAnalysisService.decode(json) == reply)
        object["key_takeaways"] = ["Evita la insulina."]
        #expect(ReportAnalysisValidator.violation(in: try ReportAnalysisParser.parse(object: object)) != nil)
    }

    @Test func missingKeyTakeawaysIsStillValid() throws {
        let reply = try ReportAnalysisParser.parse(object: ReportAnalysisFixtures.replyObject())
        #expect(reply.keyTakeaways.isEmpty)
    }

    /// Un análisis guardado antes de T-33 (sin `key_takeaways`) se sigue abriendo.
    @Test func savedAnalysisFromBeforeT33StillOpens() throws {
        let old = """
        {"caveats":["Esto es una guía informativa y no consejo médico."],"overview":"Panorama.",\
        "questions_to_explore":["¿Qué cenaste?"],"sections":[{"title":"Resumen","what_the_data_shows":"Todo en rango.",\
        "what_to_try":"Camina.","what_to_watch":"Mira la tarde.","why_it_may_happen":"Comidas regulares."}]}
        """
        let reply = try #require(ReportAnalysisService.decode(old))
        #expect(reply.keyTakeaways.isEmpty)
        #expect(reply.overview == "Panorama.")
        #expect(reply.sections.first?.whatToTry == "Camina.")
    }
}
