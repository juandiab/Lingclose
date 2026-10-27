import Foundation
import Testing
@testable import LingoCore

/// Migración v2 → v3 (T-21 §5) con datos: lo existente sobrevive y `workout_links` nace vacía. Todo sintético.
struct SchemaMigrationV2ToV3Tests {
    @Test func v2DatabaseKeepsEventsAndMealNutritionAndGetsEmptyWorkoutLinks() async throws {
        let path = try TestSupport.temporaryDatabasePath("v2")
        let mealID = TestSupport.newID(), exerciseID = TestSupport.newID()
        let at: Int64 = 1_793_110_000
        do {
            // Base v2 tal como la dejaba la app antes del §5: guiones v1 + v2 y datos reales de esquema.
            let c = try SQLiteConnection(path: path)
            try c.run("PRAGMA foreign_keys = ON")
            try c.executeScript(StoreSchema.v1)
            try c.executeScript(StoreSchema.v2)
            for (id, kind, carbs, text) in [(mealID, "meal", 45.0 as Double?, "Comida de prueba"),
                                            (exerciseID, "exercise", nil, "Correr de prueba")] {
                let edit = TestSupport.newID()
                try c.run("""
                    INSERT INTO events (event_id, kind, at_epoch_s, tz, carbs_g, text, created_at_epoch_s, updated_at_epoch_s,
                      edit_id, edited_by_app_id, synthetic)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [SQLiteValue(id), SQLiteValue(kind), SQLiteValue(at), SQLiteValue(TestSupport.tz), SQLiteValue(carbs),
                          SQLiteValue(text), SQLiteValue(at), SQLiteValue(at), SQLiteValue(edit),
                          SQLiteValue(TestSupport.appID), SQLiteValue(false)])
                try c.run("INSERT INTO edit_lineage (edit_id, parent_edit_id, event_id) VALUES (?, NULL, ?)",
                          [SQLiteValue(edit), SQLiteValue(id)])
            }
            try c.run("""
                INSERT INTO meal_nutrition (event_id, source_json, kind, name, basis_json, base_json, multiplier,
                  overrides_json, updated_at_epoch_s)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [SQLiteValue(mealID), SQLiteValue(#"{"type":"manual"}"#), SQLiteValue("food"), SQLiteValue("Plato de prueba"),
                      SQLiteValue(#"{"type":"per_100g"}"#), SQLiteValue(#"{"kcal":200,"carbs_g":30}"#), SQLiteValue(1.5),
                      SQLiteValue("{}"), SQLiteValue(at)])
            #expect(try StoreSchema.userVersion(c) == 2)
        }

        let store = try SQLiteStore(path: path)
        #expect(try await store.schemaVersion() == 3)
        #expect(try await store.tableNames() == SchemaMigrationTests.expectedTables)
        #expect(try await store.linkedWorkoutCount() == 0, "workout_links nace vacía")

        let meal = try #require(try await store.event(id: mealID))
        #expect(meal.kind == .meal && meal.carbsG == 45 && meal.text == "Comida de prueba")
        #expect(try await store.event(id: exerciseID)?.kind == .exercise)
        let nutrition = try #require(try await store.mealNutrition(eventID: mealID))
        #expect(nutrition.multiplier == 1.5 && nutrition.baseNutrients == Nutrients(kcal: 200, carbsG: 30))
        #expect(nutrition.baseNutrients.proteinG == nil)
        #expect(try await store.eventID(forWorkoutUUID: "cualquiera") == nil)

        // La tabla nueva ya acepta enlaces, y reabrir no reaplica la migración ni toca los datos.
        try await store.linkWorkout(uuid: "w-1", eventID: exerciseID, at: UTCInstant(epochSeconds: at))
        let reopened = try SQLiteStore(path: path)
        #expect(try await reopened.schemaVersion() == 3)
        #expect(try await reopened.linkedWorkoutCount() == 1)
        #expect(try await reopened.event(id: mealID) == meal)
        #expect(try await reopened.mealNutrition(eventID: mealID) == nutrition)
    }
}
