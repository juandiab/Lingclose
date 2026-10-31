import Foundation
import Testing
@testable import LingoCore

/// Tabla `report_analyses` (migración v4, T-27a).
struct ReportsStoreTests {
    private static func record(_ id: String, created: Int64, start: Int64, end: Int64,
                               status: ReportAnalysisStatus = .succeeded) -> ReportAnalysisRecord {
        ReportAnalysisRecord(id: id, createdAt: UTCInstant(epochSeconds: created), periodStart: UTCInstant(epochSeconds: start),
                             periodEnd: UTCInstant(epochSeconds: end), provider: "anthropic", model: "modelo-de-prueba",
                             requestSHA256: String(repeating: "0f", count: 32),
                             responseJSON: status == .succeeded ? #"{"overview":"sintético"}"# : nil, status: status,
                             error: status == .succeeded ? nil : "motivo de prueba")
    }

    @Test func insertListDeleteAndReopen() async throws {
        let path = try TestSupport.temporaryDatabasePath("analyses")
        let store = try SQLiteStore(path: path)
        let a1 = Self.record("a1", created: 1_000, start: 100, end: 200)
        let a2 = Self.record("a2", created: 2_000, start: 100, end: 200, status: .rejected)
        let b1 = Self.record("b1", created: 1_500, start: 300, end: 400, status: .failed)
        for r in [a1, a2, b1] { try await store.insertReportAnalysis(r) }
        await #expect(throws: (any Error).self) { try await store.insertReportAnalysis(a1) }

        #expect(try await store.reportAnalyses(periodStart: UTCInstant(epochSeconds: 100), periodEnd: UTCInstant(epochSeconds: 200)) == [a2, a1])
        #expect(try await store.reportAnalyses(overlapping: UTCInstant(epochSeconds: 150), UTCInstant(epochSeconds: 350)).map(\.id) == ["a2", "b1", "a1"])
        #expect(try await store.reportAnalyses(overlapping: UTCInstant(epochSeconds: 200), UTCInstant(epochSeconds: 300)).isEmpty)
        #expect(try await store.recentReportAnalyses(limit: 2).map(\.id) == ["a2", "b1"])

        #expect(try await store.deleteReportAnalysis(id: "a2"))
        #expect(try await store.deleteReportAnalysis(id: "a2") == false)
        let reopened = try SQLiteStore(path: path)
        #expect(try await reopened.recentReportAnalyses() == [b1, a1])
    }

    @Test func migratesV3DatabaseAdditively() async throws {
        let path = try TestSupport.temporaryDatabasePath("v3")
        let eventID = TestSupport.newID(), editID = TestSupport.newID()
        do {
            let c = try SQLiteConnection(path: path)
            try c.run("PRAGMA foreign_keys = ON")
            try c.executeScript(StoreSchema.v1)
            try c.executeScript(StoreSchema.v2)
            try c.executeScript(StoreSchema.v3)
            try c.run("""
                INSERT INTO events (event_id, kind, at_epoch_s, tz, carbs_g, text, created_at_epoch_s, updated_at_epoch_s,
                  edit_id, edited_by_app_id, synthetic)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [SQLiteValue(eventID), SQLiteValue("meal"), SQLiteValue(Int64(1_793_110_000)), SQLiteValue(TestSupport.tz),
                      SQLiteValue(30.0), SQLiteValue("Comida de prueba"), SQLiteValue(Int64(1_793_110_000)),
                      SQLiteValue(Int64(1_793_110_000)), SQLiteValue(editID), SQLiteValue(TestSupport.appID), SQLiteValue(true)])
            #expect(try StoreSchema.userVersion(c) == 3)
        }
        let store = try SQLiteStore(path: path)
        #expect(try await store.schemaVersion() == 4)
        #expect(try await store.tableNames().contains("report_analyses"))
        #expect(try await store.event(id: eventID)?.carbsG == 30)
        #expect(try await store.recentReportAnalyses().isEmpty)
        try await store.insertReportAnalysis(Self.record("x", created: 1, start: 1, end: 2))
        let reopened = try SQLiteStore(path: path)
        #expect(try await reopened.schemaVersion() == 4)
        #expect(try await reopened.recentReportAnalyses().count == 1)
    }
}
