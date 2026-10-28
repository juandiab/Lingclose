import Foundation
import Testing
@testable import LingoScan

/// Validación de la respuesta del asistente (T-25).
struct CoachingReplyParserTests {
    private func object(summary: Any? = "Resumen breve.", suggestions: Any? = [["title": "A", "body": "Uno."]],
                        caution: Any? = NSNull()) -> [String: Any] {
        var o: [String: Any] = [:]
        o["summary"] = summary
        o["suggestions"] = suggestions
        o["caution"] = caution
        return o
    }

    @Test func validObjectWithNullCaution() throws {
        let reply = try CoachingReplyParser.parse(object: object())
        #expect(reply == LLMCoachingReply(summary: "Resumen breve.", suggestions: [.init(title: "A", body: "Uno.")], caution: nil))
    }

    @Test func textWithSurroundingProseIsAccepted() throws {
        let text = "Aquí va:\n{\"summary\": \"Hola.\", \"suggestions\": [], \"caution\": \"Si persiste, consulta a un profesional.\"}\nFin"
        let reply = try CoachingReplyParser.parse(text: text)
        #expect(reply.suggestions.isEmpty)
        #expect(reply.caution == "Si persiste, consulta a un profesional.")
    }

    @Test func longTextsAreShortenedAndExtraSuggestionsDropped() throws {
        let long = String(repeating: "palabra ", count: 60)
        let many = (1...5).map { ["title": "T\($0)", "body": long] }
        let reply = try CoachingReplyParser.parse(object: object(summary: long, suggestions: many))
        #expect(reply.summary.count <= CoachingPrompt.maxSummary)
        #expect(reply.summary.hasSuffix("…"))
        #expect(reply.suggestions.count == 3)
        #expect(reply.suggestions.allSatisfy { $0.body.count <= CoachingPrompt.maxBody })
    }

    @Test func missingPartsAreRejected() {
        #expect(throws: LLMError.self) { try CoachingReplyParser.parse(object: object(summary: "  ")) }
        #expect(throws: LLMError.self) { try CoachingReplyParser.parse(object: object(suggestions: nil)) }
        #expect(throws: LLMError.self) { try CoachingReplyParser.parse(object: object(suggestions: [["title": "Sin cuerpo"]])) }
        #expect(throws: LLMError.self) { try CoachingReplyParser.parse(text: "sin json") }
    }

    @Test(arguments: [
        "Ajusta la INSULINA antes de cenar.", "Revisa tu medicación.", "Toma un fármaco.", "Una dosis pequeña.",
        "Check your medication.", "Metformina por la noche.",
    ])
    func forbiddenTermsAnywhereAreRejected(text: String) {
        #expect(throws: LLMError.self) { try CoachingReplyParser.parse(object: object(summary: text)) }
        #expect(throws: LLMError.self) { try CoachingReplyParser.parse(object: object(caution: text)) }
        #expect(throws: LLMError.self) {
            try CoachingReplyParser.parse(object: object(suggestions: [["title": "A", "body": "B"], ["title": "C", "body": "D"],
                                                                      ["title": "E", "body": "F"], ["title": "G", "body": text]]))
        }
    }

    @Test func professionalReferralIsAllowed() throws {
        let reply = try CoachingReplyParser.parse(object: object(caution: "Si los síntomas persisten, consulta a un profesional de la salud."))
        #expect(reply.caution != nil)
    }
}
