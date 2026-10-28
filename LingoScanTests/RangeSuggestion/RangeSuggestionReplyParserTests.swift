import Foundation
import Testing
@testable import LingoScan

/// El parser acepta solo rangos dentro de límites con explicación; nunca corrige cifras.
struct RangeSuggestionReplyParserTests {
    @Test func validObjectAndTextParse() throws {
        let reply = try RangeSuggestionReplyParser.parse(object: ["low_mgdl": 70, "high_mgdl": 140, "explanation": " ok "])
        #expect(reply == LLMRangeReply(low: 70, high: 140, explanation: "ok"))
        let fenced = try RangeSuggestionReplyParser.parse(text: "```json\n{\"low_mgdl\": \"75\", \"high_mgdl\": 145.0, \"explanation\": \"texto\"}\n```")
        #expect(fenced.low == 75)
        #expect(fenced.high == 145)
    }

    /// Casos inválidos como JSON (los argumentos de `@Test` deben ser `Sendable`; `[String: Any]` no lo es).
    @Test(arguments: [
        "{\"low_mgdl\": 30, \"high_mgdl\": 140, \"explanation\": \"x\"}",      // baja fuera de 50–100
        "{\"low_mgdl\": 70, \"high_mgdl\": 260, \"explanation\": \"x\"}",      // alta fuera de 100–250
        "{\"low_mgdl\": 100, \"high_mgdl\": 115, \"explanation\": \"x\"}",     // separación < 20
        "{\"low_mgdl\": 70, \"high_mgdl\": 140, \"explanation\": \"   \"}",    // sin explicación
        "{\"low_mgdl\": 70.5, \"high_mgdl\": 140, \"explanation\": \"x\"}",    // no entero
        "{\"high_mgdl\": 140, \"explanation\": \"x\"}",                        // falta la baja
    ])
    func invalidObjectsAreRejected(json: String) {
        do {
            _ = try RangeSuggestionReplyParser.parse(text: json)
            Issue.record("debía fallar: \(json)")
        } catch let error as LLMError {
            guard case .invalidResponse = error else { Issue.record("esperaba invalidResponse, llegó \(error)"); return }
        } catch {
            Issue.record("error inesperado \(error)")
        }
    }

    @Test func textWithoutJSONIsInvalid() {
        #expect(throws: LLMError.self) { try RangeSuggestionReplyParser.parse(text: "No puedo ayudarte con eso.") }
    }
}
