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
}
