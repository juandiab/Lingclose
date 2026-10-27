import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// Importación de entrenamientos (T-21 §5). Todo sintético.
struct WorkoutImporterTests {
    @Test func reimportingDoesNotDuplicate() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "WorkoutImporterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try SQLiteStore(path: dir.appending(path: "store.sqlite").path(percentEncoded: false))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = UTCInstant(now.addingTimeInterval(-7_200))
        let workouts = ["a", "b"].map {
            WorkoutSummary(uuid: "w-\($0)", activityName: "Correr", start: start, end: start.adding(seconds: 1_800),
                           durationMin: 30, activeEnergyKcal: 300)
        }
        let source = FakeWorkoutSource(workouts: workouts)
        let defaults = try #require(UserDefaults(suiteName: "WorkoutImporterTests-\(UUID().uuidString)"))
        let importer = WorkoutImporter(source: source, store: store, defaults: defaults, now: { now })

        #expect(try await importer.importNew() == WorkoutImportReport(imported: 2, updated: 0, unchanged: 0))
        #expect(try await importer.importNew() == WorkoutImportReport(imported: 0, updated: 0, unchanged: 2))
        let events = try await store.events(in: start...start)
        #expect(events.count == 2 && events.allSatisfy { $0.kind == .exercise })
        #expect(await importer.status().totalImported == 2)
        #expect(source.reads == 2)
    }
}
