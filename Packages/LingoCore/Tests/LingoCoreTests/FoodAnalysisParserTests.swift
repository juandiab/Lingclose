import Foundation
import Testing
@testable import LingoCore

/// T-21: respuesta estructurada del modelo → `FoodAnalysis`. Desconocido es `nil`, nunca 0.
struct FoodAnalysisParserTests {
    @Test func foodWithEstimatedServing() throws {
        let json = """
        {"kind":"food","name":"Arepa con queso","basis":{"type":"estimated_serving","description":"1 arepa mediana","grams":120},
         "nutrients":{"kcal":320,"carbs_g":38.5,"protein_g":"9","fat_g":null},"confidence":0.7,"assumptions":"Queso campesino, sin mantequilla"}
        """
        let a = try FoodAnalysisParser.parse(text: json)
        #expect(a.kind == .food && a.name == "Arepa con queso")
        #expect(a.basis == .estimatedServing(description: "1 arepa mediana", grams: 120))
        #expect(a.baseNutrients == Nutrients(kcal: 320, carbsG: 38.5, proteinG: 9, fatG: nil))
        #expect(a.confidence == 0.7 && a.assumptions?.hasPrefix("Queso") == true)
        #expect(a.hasAnyNutrient)
    }

    @Test func labelKeepsItsBasisAndUnreadableAsNil() throws {
        let json = """
        ```json
        {"kind":"nutrition_label","name":"Galletas","basis":{"type":"per_100g"},
         "nutrients":{"kcal":"480 kcal","carbs_g":"62,0 g","protein_g":"unknown"},"unreadable":["protein_g","fat_g"]}
        ```
        """
        let a = try FoodAnalysisParser.parse(text: json)
        #expect(a.kind == .nutritionLabel && a.basis == .per100g && a.basis?.isLabel == true)
        #expect(a.baseNutrients == Nutrients(kcal: 480, carbsG: 62, proteinG: nil, fatG: nil))
        #expect(a.unreadableFields == ["protein_g", "fat_g"])
        #expect(a.confidence == nil)
    }

    @Test func notFoodIgnoresNumbers() throws {
        let a = try FoodAnalysisParser.parse(text: "Texto previo {\"kind\":\"not_food\",\"nutrients\":{\"kcal\":10}} texto posterior")
        #expect(a.kind == .notFood && a.basis == nil && a.baseNutrients.isUnknown && !a.hasAnyNutrient)
    }

    @Test func rejectsWhatMustNotBeInvented() {
        #expect(throws: FoodAnalysisParserError.noJSON) { try FoodAnalysisParser.parse(text: "sin json") }
        #expect(throws: FoodAnalysisParserError.missingKind) { try FoodAnalysisParser.parse(text: "{\"name\":\"x\"}") }
        #expect(throws: FoodAnalysisParserError.unknownKind("drink")) { try FoodAnalysisParser.parse(text: "{\"kind\":\"drink\"}") }
        #expect(throws: FoodAnalysisParserError.labelWithoutBasis) {
            try FoodAnalysisParser.parse(text: "{\"kind\":\"nutrition_label\",\"nutrients\":{\"kcal\":100}}")
        }
        #expect(throws: FoodAnalysisParserError.valueOutOfRange(field: "kcal", value: -5)) {
            try FoodAnalysisParser.parse(text: "{\"kind\":\"food\",\"nutrients\":{\"kcal\":-5}}")
        }
        #expect(throws: FoodAnalysisParserError.valueOutOfRange(field: "kcal", value: 9_000)) {
            try FoodAnalysisParser.parse(text: "{\"kind\":\"food\",\"nutrients\":{\"kcal\":9000}}")
        }
        #expect(throws: FoodAnalysisParserError.notANumber(field: "carbs_g")) {
            try FoodAnalysisParser.parse(text: "{\"kind\":\"food\",\"nutrients\":{\"carbs_g\":true}}")
        }
        #expect(throws: FoodAnalysisParserError.notANumber(field: "carbs_g")) {
            try FoodAnalysisParser.parse(text: "{\"kind\":\"food\",\"nutrients\":{\"carbs_g\":\"mucho\"}}")
        }
        #expect(throws: FoodAnalysisParserError.unknownBasis("per_cup")) {
            try FoodAnalysisParser.parse(text: "{\"kind\":\"food\",\"basis\":{\"type\":\"per_cup\"}}")
        }
    }

    @Test func foodWithoutBasisOrNumbersIsValidButEmpty() throws {
        let a = try FoodAnalysisParser.parse(text: "{\"kind\":\"food\",\"name\":\"Sopa\",\"nutrients\":{\"kcal\":null}}")
        #expect(a.basis == .estimatedServing(description: nil, grams: nil))
        #expect(!a.hasAnyNutrient, "sin cifras: la UI explica por qué no hay ajuste")
        #expect(a.baseNutrients.kcal == nil, "null nunca se convierte en 0")
    }

    @Test func confidenceOutOfRangeBecomesUnknown() throws {
        let a = try FoodAnalysisParser.parse(text: "{\"kind\":\"food\",\"confidence\":1.7}")
        #expect(a.confidence == nil)
    }

    @Test func scalingAlwaysFromBase() {
        let base = Nutrients(kcal: 200, carbsG: 30, proteinG: nil, fatG: 8)
        let x15 = base.scaled(by: 1.5)
        #expect(x15 == Nutrients(kcal: 300, carbsG: 45, proteinG: nil, fatG: 12))
        #expect(base.scaled(by: 1.0) == base)
        let overrides = Nutrients(carbsG: 40)
        #expect(x15.overridden(by: overrides) == Nutrients(kcal: 300, carbsG: 40, proteinG: nil, fatG: 12))
    }

    @Test func analysisRoundTripsThroughCodable() throws {
        let a = FoodAnalysis(kind: .nutritionLabel, name: "Yogur", basis: .perServing(description: "1 vaso", grams: 150),
                             baseNutrients: Nutrients(kcal: 90, carbsG: 12), confidence: 0.9, assumptions: nil, unreadableFields: ["fat_g"])
        let data = try JSONEncoder().encode(a)
        #expect(try JSONDecoder().decode(FoodAnalysis.self, from: data) == a)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["basis"] as? [String: Any])?["type"] as? String == "per_serving")
        #expect(try FoodAnalysisParser.parse(data) == a, "el JSON que emitimos también lo acepta el parser")
    }
}
