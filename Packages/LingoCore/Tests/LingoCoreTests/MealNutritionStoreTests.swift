import Foundation
import Testing
@testable import LingoCore

/// Persistencia de `meal_nutrition` (T-21 §3). Todo sintético.
struct MealNutritionStoreTests {
    static let at = UTCInstant(epochSeconds: 1_793_110_000)

    static func meal(_ eventID: String, editID: String = TestSupport.newID(), parent: String? = nil,
                     carbs: Double? = nil, text: String? = "Comida de prueba") -> DiaryEvent {
        DiaryEvent(eventID: eventID, kind: .meal, at: at, tz: TestSupport.tz, carbsG: carbs, text: text,
                   createdAt: at, updatedAt: at.adding(seconds: 60), editID: editID, parentEditID: parent,
                   editedByAppID: TestSupport.appID, synthetic: false)
    }

    static func nutrition(_ eventID: String, multiplier: Double = 1.5, overrides: Nutrients = Nutrients(proteinG: 11),
                          base: Nutrients = Nutrients(kcal: 200, carbsG: 30, proteinG: nil, fatG: 5)) -> MealNutritionRecord {
        MealNutritionRecord(eventID: eventID, source: .label(provider: "openai", model: "modelo-prueba"), kind: .nutritionLabel,
                            name: "Galleta de prueba", basis: .per100g, baseNutrients: base, multiplier: multiplier,
                            overrides: overrides, assumptions: nil, confidence: nil, analyzedAt: nil,
                            updatedAt: at.adding(seconds: 90))
    }

    @Test func saveAndReopenKeepsBaseMultiplierOverridesAndUnknowns() async throws {
        let path = try TestSupport.temporaryDatabasePath()
        let id = TestSupport.newID()
        let record = Self.nutrition(id)
        do {
            let store = try SQLiteStore(path: path)
            #expect(try await store.saveMeal(event: Self.meal(id), nutrition: record) == .inserted)
        }
        let reopened = try SQLiteStore(path: path)
        let back = try #require(try await reopened.mealNutrition(eventID: id))
        #expect(back == record)
        #expect(back.baseNutrients == Nutrients(kcal: 200, carbsG: 30, proteinG: nil, fatG: 5))
        #expect(back.baseNutrients.proteinG == nil, "desconocido sigue desconocido, no 0")
        #expect(back.multiplier == 1.5)
        #expect(back.overrides == Nutrients(proteinG: 11))
        #expect(back.analyzedAt == nil && back.confidence == nil && back.assumptions == nil)
        #expect(back.basis == .per100g && back.kind == .nutritionLabel)
    }

    @Test func saveMealWritesAdjustedCarbsOnEvent() async throws {
        let store = try TestSupport.makeStore()
        let id = TestSupport.newID(), e1 = TestSupport.newID(), e2 = TestSupport.newID()
        // El evento llega con un carbs_g cualquiera: manda el efectivo del registro (30 × 1,5).
        try await store.saveMeal(event: Self.meal(id, editID: e1, carbs: 999), nutrition: Self.nutrition(id))
        #expect(try await store.event(id: id)?.carbsG == 45)

        // Nueva edición: corrección manual de carbohidratos y otro multiplicador.
        let edited = Self.nutrition(id, multiplier: 2.0, overrides: Nutrients(carbsG: 50))
        #expect(try await store.saveMeal(event: Self.meal(id, editID: e2, parent: e1), nutrition: edited) == .tookDescendant)
        #expect(try await store.event(id: id)?.carbsG == 50)
        #expect(try await store.mealNutrition(eventID: id) == edited)

        // Carbohidratos desconocidos → carbs_g NULL, nunca 0.
        let unknownID = TestSupport.newID()
        try await store.saveMeal(event: Self.meal(unknownID), nutrition: Self.nutrition(unknownID, overrides: .unknown,
                                                                                         base: Nutrients(kcal: 150)))
        #expect(try await store.event(id: unknownID)?.carbsG == nil)
    }

    @Test func olderEditDoesNotOverwriteNutrition() async throws {
        let store = try TestSupport.makeStore()
        let id = TestSupport.newID(), e1 = TestSupport.newID(), e2 = TestSupport.newID()
        let current = Self.nutrition(id, multiplier: 2.0)
        try await store.saveMeal(event: Self.meal(id, editID: e1), nutrition: Self.nutrition(id))
        try await store.saveMeal(event: Self.meal(id, editID: e2, parent: e1), nutrition: current)
        // Reenviar la edición antigua no la resucita ni cambia la fila.
        #expect(try await store.saveMeal(event: Self.meal(id, editID: e1), nutrition: Self.nutrition(id, multiplier: 4.0)) == .keptNewerLocal)
        #expect(try await store.mealNutrition(eventID: id) == current)
        #expect(try await store.event(id: id)?.carbsG == 60)
    }

    @Test func invalidInputIsRejectedAtomically() async throws {
        let store = try TestSupport.makeStore()
        let id = TestSupport.newID()
        await #expect(throws: StoreError.self) {
            try await store.saveMeal(event: Self.meal(id), nutrition: Self.nutrition(TestSupport.newID()))
        }
        await #expect(throws: StoreError.self) {
            try await store.saveMeal(event: Self.meal(id), nutrition: Self.nutrition(id, multiplier: 5.5))
        }
        var note = Self.meal(id)
        note.kind = .note
        await #expect(throws: StoreError.self) { try await store.saveMeal(event: note, nutrition: Self.nutrition(id)) }
        #expect(try await store.event(id: id) == nil, "nada se escribe si el registro es inválido")
        // Sin evento no hay fila: la clave foránea lo impide.
        await #expect(throws: (any Error).self) { try await store.upsertMealNutrition(Self.nutrition(id)) }
        #expect(try await store.mealNutrition(eventID: id) == nil)
    }

    @Test func deletingNutritionKeepsEvent() async throws {
        let store = try TestSupport.makeStore()
        let id = TestSupport.newID()
        try await store.saveMeal(event: Self.meal(id), nutrition: Self.nutrition(id))
        try await store.deleteMealNutrition(eventID: id)
        #expect(try await store.mealNutrition(eventID: id) == nil)
        let event = try #require(try await store.event(id: id))
        #expect(event.kind == .meal && event.carbsG == 45)
    }

    @Test func mealWithoutNutritionRowStillReads() async throws {
        let store = try TestSupport.makeStore()
        let id = TestSupport.newID()
        try await store.upsertEvent(Self.meal(id, carbs: 35, text: "Registro antiguo"))
        #expect(try await store.mealNutrition(eventID: id) == nil)
        let event = try #require(try await store.event(id: id))
        #expect(event.carbsG == 35 && event.text == "Registro antiguo")
        #expect(try await store.events(in: Self.at.adding(seconds: -1)...Self.at.adding(seconds: 1)).map(\.eventID) == [id])
    }

    @Test func upsertMealNutritionReplacesRow() async throws {
        let store = try TestSupport.makeStore()
        let id = TestSupport.newID()
        try await store.upsertEvent(Self.meal(id, carbs: 35))
        try await store.upsertMealNutrition(Self.nutrition(id))
        let manual = MealNutritionRecord(eventID: id, source: .manual, kind: .food, basis: .estimatedServing(description: nil, grams: nil),
                                         baseNutrients: Nutrients(carbsG: 35), updatedAt: Self.at)
        try await store.upsertMealNutrition(manual)
        #expect(try await store.mealNutrition(eventID: id) == manual)
    }

    @Test func archiveExportIgnoresMealNutrition() async throws {
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path, now: ArchiveTestSupport.fixedNow)
        _ = try await ArchiveRoundTripTests.populate(store)
        let id = TestSupport.newID()
        try await store.saveMeal(event: Self.meal(id), nutrition: Self.nutrition(id))

        let dest = try ArchiveTestSupport.temporaryDirectory("destino")
        let result = try await ArchiveRoundTripTests.exporter(store, path: path).export(to: dest)
        #expect(result.verified, "\(result.verificationFailure ?? "")")
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: result.url.path))
        #expect(files == ["manifest.json", "sessions.json", "readings.ndjson", "events.ndjson", "health_export_ledger.ndjson",
                          "conflicts.ndjson", "readings.csv", "README.md"])
        #expect(result.manifest.schemaVersion == 1, "el esquema del paquete no cambia con la migración v2 de SQLite")
        let events = try String(contentsOf: result.url.appendingPathComponent("events.ndjson"), encoding: .utf8)
        let line = try #require(events.split(separator: "\n").first { $0.contains(id) })
        for leaked in ["base_nutrients", "multiplier", "overrides", "basis", "Galleta de prueba", "modelo-prueba"] {
            #expect(!events.contains(leaked), "events.ndjson no debe llevar \(leaked)")
        }
        let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(object["carbs_g"] as? Double == 45)
    }
}
