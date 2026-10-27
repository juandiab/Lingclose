import Foundation
import Testing
@testable import LingoCore

/// Reglas puras del registro de nutrición y del slider de porciones (T-21 §3). Cifras inventadas.
struct MealNutritionRecordTests {
    static func record(base: Nutrients = Nutrients(kcal: 200, carbsG: 30, proteinG: 8, fatG: 5),
                       multiplier: Double = 1.0, overrides: Nutrients = .unknown) -> MealNutritionRecord {
        MealNutritionRecord(eventID: "evento-prueba", source: .llm(provider: "anthropic", model: "modelo-prueba"), kind: .food,
                            name: "Plato de prueba", basis: .estimatedServing(description: "1 porción", grams: 150),
                            baseNutrients: base, multiplier: multiplier, overrides: overrides,
                            assumptions: "Supuesto de prueba", confidence: 0.7,
                            analyzedAt: UTCInstant(epochSeconds: 1_793_110_000), updatedAt: UTCInstant(epochSeconds: 1_793_110_060))
    }

    @Test func scalesFromBaseAndReturnsExactlyToBase() {
        var r = Self.record(multiplier: 1.5)
        #expect(r.effectiveNutrients.kcal == 300)
        #expect(r.effectiveNutrients.carbsG == 45)
        #expect(r.baseNutrients == Nutrients(kcal: 200, carbsG: 30, proteinG: 8, fatG: 5), "la base no se toca")

        r.multiplier = 1.0
        #expect(r.effectiveNutrients == r.baseNutrients)
        #expect(r.effectiveNutrients.kcal == 200 && r.effectiveNutrients.carbsG == 30)

        // Ir y volver muchas veces no acumula error: siempre se parte de la base.
        for m in stride(from: 1.0, through: 5.0, by: 0.1) { r.multiplier = PortionAdjustment.clamp(m) }
        r.multiplier = 1.0
        #expect(r.effectiveNutrients == r.baseNutrients)
    }

    @Test func manualCarbsOverrideSurvivesMultiplierChanges() {
        var r = Self.record(multiplier: 1.5, overrides: Nutrients(carbsG: 52))
        #expect(r.effectiveNutrients.carbsG == 52)
        #expect(r.effectiveNutrients.kcal == 300)
        r.multiplier = 3.0
        #expect(r.effectiveNutrients.carbsG == 52, "la corrección manual no la toca el slider")
        #expect(r.effectiveNutrients.kcal == 600)
        r.multiplier = 1.0
        #expect(r.effectiveNutrients.carbsG == 52)
        #expect(r.effectiveNutrients.kcal == 200)

        // "Restablecer" el campo: quitar la corrección vuelve a base × multiplicador.
        r.overrides[.carbsG] = nil
        #expect(r.effectiveNutrients.carbsG == 30)
    }

    @Test func unknownStaysUnknown() {
        let r = Self.record(base: Nutrients(kcal: 120, carbsG: nil, proteinG: nil, fatG: 4), multiplier: 2.5)
        #expect(r.effectiveNutrients.carbsG == nil)
        #expect(r.effectiveNutrients.proteinG == nil)
        #expect(r.effectiveNutrients.kcal == 300 && r.effectiveNutrients.fatG == 10)
        #expect(PortionAdjustment.display(r.effectiveNutrients.carbsG, field: .carbsG) == nil)
        #expect(PortionAdjustment.adjusted(.unknown, multiplier: 4, overrides: .unknown).isUnknown)
    }

    @Test func clampRoundsToTenthsAndLimitsRange() {
        #expect(PortionAdjustment.clamp(0.96) == 1.0)
        #expect(PortionAdjustment.clamp(0.5) == 0.5, "media porción es el mínimo")
        #expect(PortionAdjustment.clamp(0.3) == 0.5)
        #expect(PortionAdjustment.clamp(0.75) == 0.8)
        #expect(Nutrients(kcal: 200, carbsG: 30).scaled(by: 0.5) == Nutrients(kcal: 100, carbsG: 15))
        #expect(PortionAdjustment.clamp(5.3) == 5.0)
        // Redondeo documentado: a la décima más cercana, mitades lejos de cero.
        #expect(PortionAdjustment.clamp(1.25) == 1.3)
        #expect(PortionAdjustment.clamp(1.24) == 1.2)
        #expect(PortionAdjustment.clamp(2.0) == 2.0)
        #expect(PortionAdjustment.clamp(0) == 0.5, "por debajo del mínimo: media porción")
        #expect(PortionAdjustment.clamp(-3) == 0.5)
        #expect(PortionAdjustment.clamp(.nan) == 1.0)
        #expect(PortionAdjustment.clamp(.infinity) == 1.0)
        // Cada paso del slider da exactamente el literal de 1 decimal.
        for tenths in 10...50 {
            #expect(PortionAdjustment.clamp(Double(tenths) * 0.1) == Double(tenths) / 10)
        }
    }

    @Test func displayFormatsKcalAndGrams() {
        #expect(PortionAdjustment.display(299.6, field: .kcal) == "300")
        #expect(PortionAdjustment.display(300, field: .kcal) == "300")
        #expect(PortionAdjustment.display(45, field: .carbsG) == "45")
        #expect(PortionAdjustment.display(12.25, field: .proteinG) == "12,3")
        #expect(PortionAdjustment.display(44.99, field: .fatG) == "45")
        #expect(PortionAdjustment.display(0.4, field: .carbsG) == "0,4")
        #expect(PortionAdjustment.display(0, field: .carbsG) == "0", "0 conocido no es desconocido")
        #expect(PortionAdjustment.display(nil, field: .kcal) == nil)
    }

    @Test func codableUsesSnakeCaseAndRoundTrips() throws {
        let r = Self.record(base: Nutrients(kcal: 200, carbsG: nil, proteinG: 8, fatG: 5), multiplier: 1.5,
                            overrides: Nutrients(carbsG: 40))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(r), as: UTF8.self)
        for key in ["\"event_id\"", "\"base_nutrients\"", "\"analyzed_at_utc\"", "\"updated_at_utc\"", "\"carbs_g\"",
                    "\"type\":\"llm\"", "\"provider\":\"anthropic\""] {
            #expect(json.contains(key), "falta \(key) en \(json)")
        }
        #expect(!json.contains("effective"), "lo derivado no se serializa")
        let back = try JSONDecoder().decode(MealNutritionRecord.self, from: Data(json.utf8))
        #expect(back == r)
        #expect(back.baseNutrients.carbsG == nil)

        for source in [MealNutritionSource.manual, .label(provider: "openai", model: "m"), .llm(provider: "gemini", model: "g")] {
            #expect(try JSONDecoder().decode(MealNutritionSource.self, from: encoder.encode(source)) == source)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MealNutritionSource.self, from: Data(#"{"type":"otro"}"#.utf8))
        }
    }
}
