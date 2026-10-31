import Foundation
import Testing
@testable import LingoCore

struct SchemaMigrationTests {
    static let expectedTables = ["archives", "conflicts", "edit_lineage", "event_log", "events",
                                 "health_export_ledger", "imported_archives", "meal_nutrition", "readings", "report_analyses", "sensor_sessions", "workout_links"]

    @Test func freshDatabaseGetsCurrentSchemaWithWALAndForeignKeys() async throws {
        let store = try TestSupport.makeStore()
        #expect(try await store.schemaVersion() == 4)
        #expect(SQLiteStore.currentSchemaVersion == 4)
        #expect(try await store.journalMode() == "wal")
        #expect(try await store.foreignKeysEnabled())
        #expect(try await store.tableNames() == Self.expectedTables)
    }

    @Test func migratesV0DatabaseAndKeepsUnrelatedData() async throws {
        let path = try TestSupport.temporaryDatabasePath("v0")
        do {
            // v0: base existente sin esquema de LingoScan (user_version 0) con una tabla ajena.
            let c = try SQLiteConnection(path: path)
            try c.executeScript("CREATE TABLE legacy_note (t TEXT); INSERT INTO legacy_note VALUES ('hola');")
            #expect(try StoreSchema.userVersion(c) == 0)
        }
        let store = try SQLiteStore(path: path)
        #expect(try await store.schemaVersion() == 4)
        #expect(Set(try await store.tableNames()) == Set(Self.expectedTables + ["legacy_note"]))

        // Reabrir no reaplica la migración (fallaría con "table already exists").
        let reopened = try SQLiteStore(path: path)
        #expect(try await reopened.schemaVersion() == 4)
        let c = try SQLiteConnection(path: path)
        #expect(try c.queryFirst("SELECT t FROM legacy_note") { $0.text(0) } == "hola")
    }

    @Test func refusesDatabaseFromFutureSchema() throws {
        let path = try TestSupport.temporaryDatabasePath("future")
        do {
            let c = try SQLiteConnection(path: path)
            try c.executeScript("PRAGMA user_version = 99;")
        }
        #expect(throws: StoreError.schemaTooNew(found: 99, supported: 4)) { try SQLiteStore(path: path) }
    }

    @Test func migratesV1DatabaseToCurrentKeepingEvents() async throws {
        let path = try TestSupport.temporaryDatabasePath("v1")
        let eventID = TestSupport.newID(), editID = TestSupport.newID()
        let at: Int64 = 1_793_110_000
        do {
            // Base v1 tal como la dejaba la app antes de T-21: solo el guion v1 y un evento `meal` sintético.
            let c = try SQLiteConnection(path: path)
            try c.run("PRAGMA foreign_keys = ON")
            try c.executeScript(StoreSchema.v1)
            try c.run("""
                INSERT INTO events (event_id, kind, at_epoch_s, tz, carbs_g, text, created_at_epoch_s, updated_at_epoch_s,
                  edit_id, edited_by_app_id, synthetic)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [SQLiteValue(eventID), SQLiteValue("meal"), SQLiteValue(at), SQLiteValue(TestSupport.tz), SQLiteValue(42.5),
                      SQLiteValue("Comida de prueba"), SQLiteValue(at), SQLiteValue(at), SQLiteValue(editID),
                      SQLiteValue(TestSupport.appID), SQLiteValue(false)])
            try c.run("INSERT INTO edit_lineage (edit_id, parent_edit_id, event_id) VALUES (?, NULL, ?)",
                      [SQLiteValue(editID), SQLiteValue(eventID)])
            #expect(try StoreSchema.userVersion(c) == 1)
        }
        let store = try SQLiteStore(path: path)
        #expect(try await store.schemaVersion() == 4)
        #expect(try await store.tableNames() == Self.expectedTables)
        let event = try #require(try await store.event(id: eventID))
        #expect(event.kind == .meal && event.carbsG == 42.5 && event.text == "Comida de prueba" && event.editID == editID)
        #expect(try await store.editAncestors(of: event) == [])
        #expect(try await store.mealNutrition(eventID: eventID) == nil)

        let reopened = try SQLiteStore(path: path)
        #expect(try await reopened.schemaVersion() == 4)
        #expect(try await reopened.event(id: eventID) == event)
    }

    @Test func readingWithoutSessionIsRejected() async throws {
        let store = try TestSupport.makeStore()
        let orphan = TestSupport.reading(TestSupport.session(), lc: 100, raw: TestSupport.raw(uncapped: 100), origin: .live)
        await #expect(throws: StoreError.unknownSession(sessionID: orphan.sessionID)) { try await store.insertReading(orphan) }
    }
}
