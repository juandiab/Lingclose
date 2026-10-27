import Foundation
import Testing
@testable import LingoCore

struct SchemaMigrationTests {
    static let expectedTables = ["archives", "conflicts", "edit_lineage", "event_log", "events",
                                 "health_export_ledger", "imported_archives", "readings", "sensor_sessions"]

    @Test func freshDatabaseGetsSchemaV1WithWALAndForeignKeys() async throws {
        let store = try TestSupport.makeStore()
        #expect(try await store.schemaVersion() == 1)
        #expect(SQLiteStore.currentSchemaVersion == 1)
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
        #expect(try await store.schemaVersion() == 1)
        #expect(Set(try await store.tableNames()) == Set(Self.expectedTables + ["legacy_note"]))

        // Reabrir no reaplica la migración (fallaría con "table already exists").
        let reopened = try SQLiteStore(path: path)
        #expect(try await reopened.schemaVersion() == 1)
        let c = try SQLiteConnection(path: path)
        #expect(try c.queryFirst("SELECT t FROM legacy_note") { $0.text(0) } == "hola")
    }

    @Test func refusesDatabaseFromFutureSchema() throws {
        let path = try TestSupport.temporaryDatabasePath("future")
        do {
            let c = try SQLiteConnection(path: path)
            try c.executeScript("PRAGMA user_version = 99;")
        }
        #expect(throws: StoreError.schemaTooNew(found: 99, supported: 1)) { try SQLiteStore(path: path) }
    }

    @Test func readingWithoutSessionIsRejected() async throws {
        let store = try TestSupport.makeStore()
        let orphan = TestSupport.reading(TestSupport.session(), lc: 100, raw: TestSupport.raw(uncapped: 100), origin: .live)
        await #expect(throws: StoreError.unknownSession(sessionID: orphan.sessionID)) { try await store.insertReading(orphan) }
    }
}
