import Foundation
import LingoCore

/// Convierte la respuesta estructurada del modelo en `LLMRangeReply`. Rechaza, con `LLMError.invalidResponse`,
/// todo lo que no cumpla el contrato: claves ausentes, no enteros, fuera de `RangeSuggestionBounds`,
/// separación menor de 20 mg/dL o explicación vacía. Nunca corrige las cifras del modelo: una respuesta
/// fuera de límites se descarta y se muestra el error (sin reintentos).
enum RangeSuggestionReplyParser {
    static func parse(text: String) throws -> LLMRangeReply {
        guard let objectText = FoodAnalysisParser.firstJSONObject(in: text),
              let object = try? JSONSerialization.jsonObject(with: Data(objectText.utf8)) as? [String: Any] else {
            throw LLMError.invalidResponse(String(localized: "rangeSuggestion.parse.noJSON", defaultValue: "la respuesta no contiene un objeto JSON"))
        }
        return try parse(object: object)
    }

    static func parse(object: [String: Any]) throws -> LLMRangeReply {
        let low = try integer(object["low_mgdl"], field: "low_mgdl")
        let high = try integer(object["high_mgdl"], field: "high_mgdl")
        guard let explanation = (object["explanation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !explanation.isEmpty else {
            throw LLMError.invalidResponse(String(localized: "rangeSuggestion.parse.missingExplanation", defaultValue: "falta la explicación"))
        }
        guard RangeSuggestionBounds.isValid(low: low, high: high) else {
            throw LLMError.invalidResponse(String(
                localized: "rangeSuggestion.parse.outOfBounds",
                defaultValue: "rango \(low)–\(high) fuera de los límites permitidos"
            ))
        }
        return LLMRangeReply(low: low, high: high, explanation: explanation)
    }

    private static func integer(_ raw: Any?, field: String) throws -> Int {
        switch raw {
        case let number as NSNumber:
            let value = number.doubleValue
            guard value.isFinite, value == value.rounded() else {
                throw LLMError.invalidResponse(String(localized: "rangeSuggestion.parse.notInteger", defaultValue: "\(field) no es entero"))
            }
            return Int(value)
        case let text as String:
            guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else {
                throw LLMError.invalidResponse(String(localized: "rangeSuggestion.parse.notInteger", defaultValue: "\(field) no es entero"))
            }
            return value
        default:
            throw LLMError.invalidResponse(String(localized: "rangeSuggestion.parse.missingField", defaultValue: "falta \(field)"))
        }
    }
}
