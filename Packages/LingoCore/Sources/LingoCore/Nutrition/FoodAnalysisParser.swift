import Foundation

/// Convierte la respuesta estructurada del modelo (JSON del esquema de `docs/T-21.md` §2) en `FoodAnalysis`.
///
/// Reglas: una clave ausente, `null`, o una cadena como "unknown"/"n/a"/"" es **desconocido** (`nil`); un
/// número en cadena ("12,5") se acepta; negativos, no finitos o fuera de `NutrientLimits` se rechazan;
/// `not_food` ignora nutrientes y base; una etiqueta sin `basis` se rechaza. El JSON puede venir entre
/// vallas ```json``` o rodeado de texto: se toma el primer objeto `{…}` balanceado.
public enum FoodAnalysisParser {
    public static func parse(_ data: Data) throws -> FoodAnalysis {
        guard let text = String(data: data, encoding: .utf8) else { throw FoodAnalysisParserError.noJSON }
        return try parse(text: text)
    }

    public static func parse(text: String) throws -> FoodAnalysis {
        guard let objectText = firstJSONObject(in: text) else { throw FoodAnalysisParserError.noJSON }
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: Data(objectText.utf8)) as? [String: Any] else {
                throw FoodAnalysisParserError.malformedJSON("la raíz no es un objeto")
            }
            object = parsed
        } catch let error as FoodAnalysisParserError {
            throw error
        } catch {
            throw FoodAnalysisParserError.malformedJSON(String(describing: type(of: error)))
        }
        return try parse(object: object)
    }

    public static func parse(object: [String: Any]) throws -> FoodAnalysis {
        guard let kindRaw = string(object["kind"]) else { throw FoodAnalysisParserError.missingKind }
        guard let kind = FoodAnalysisKind(rawValue: kindRaw.lowercased()) else { throw FoodAnalysisParserError.unknownKind(kindRaw) }
        let name = string(object["name"])
        let assumptions = string(object["assumptions"])
        let confidence = try number(object["confidence"], field: "confidence").flatMap {
            NutrientLimits.confidence.contains($0) ? $0 : nil
        }
        let unreadable = (object["unreadable"] as? [Any])?.compactMap { string($0) } ?? []

        if kind == .notFood {
            return FoodAnalysis(kind: .notFood, name: name, basis: nil, baseNutrients: .unknown,
                                confidence: confidence, assumptions: assumptions, unreadableFields: unreadable)
        }

        let basis = try parseBasis(object["basis"], kind: kind)
        let nutrientsObject = object["nutrients"] as? [String: Any] ?? [:]
        var nutrients = Nutrients()
        for field in NutrientField.allCases {
            let value = try number(nutrientsObject[field.rawValue], field: field.rawValue)
            if let value, !NutrientLimits.range(for: field).contains(value) {
                throw FoodAnalysisParserError.valueOutOfRange(field: field.rawValue, value: value)
            }
            nutrients[field] = value
        }
        return FoodAnalysis(kind: kind, name: name, basis: basis, baseNutrients: nutrients,
                            confidence: confidence, assumptions: assumptions, unreadableFields: unreadable)
    }

    // MARK: - Partes

    private static func parseBasis(_ raw: Any?, kind: FoodAnalysisKind) throws -> PortionBasis {
        guard let object = raw as? [String: Any], let type = string(object["type"]) else {
            // Comida sin base explícita: el modelo propuso cifras "por ración" sin describirla.
            if kind == .food { return .estimatedServing(description: nil, grams: nil) }
            throw FoodAnalysisParserError.labelWithoutBasis
        }
        let grams = try number(object["grams"], field: "basis.grams")
        if let grams, !NutrientLimits.basisGrams.contains(grams) {
            throw FoodAnalysisParserError.valueOutOfRange(field: "basis.grams", value: grams)
        }
        guard var basis = PortionBasis(typeName: type.lowercased(), description: string(object["description"]), grams: grams) else {
            throw FoodAnalysisParserError.unknownBasis(type)
        }
        // Una comida no puede venir "por 100 g" sin que el usuario lo sepa: se respeta tal cual (la UI lo explica).
        if kind == .food, case .perServing(let d, let g) = basis { basis = .estimatedServing(description: d, grams: g) }
        return basis
    }

    static let unknownStrings: Set<String> = ["", "unknown", "desconocido", "n/a", "na", "null", "none", "-", "—", "?"]

    /// Número, `nil` para desconocido, o error si trae otra cosa.
    static func number(_ raw: Any?, field: String) throws -> Double? {
        switch raw {
        case nil, is NSNull:
            return nil
        case let n as NSNumber:
            // JSONSerialization usa NSNumber también para booleanos; `true` no es una cifra.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { throw FoodAnalysisParserError.notANumber(field: field) }
            let d = n.doubleValue
            guard d.isFinite else { throw FoodAnalysisParserError.valueOutOfRange(field: field, value: d) }
            return d
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if unknownStrings.contains(trimmed) { return nil }
            let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: "g", with: "").replacingOccurrences(of: "kcal", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let d = Double(normalized), d.isFinite else { throw FoodAnalysisParserError.notANumber(field: field) }
            return d
        default:
            throw FoodAnalysisParserError.notANumber(field: field)
        }
    }

    static func string(_ raw: Any?) -> String? {
        guard let s = raw as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return unknownStrings.contains(t.lowercased()) ? nil : t
    }

    /// Primer objeto `{…}` balanceado, respetando cadenas y escapes.
    static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let ch = text[index]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
