import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// Lo que el importador nunca hace y lo que no guarda sin permiso (T-21 §5). Todo sintético.
struct WorkoutImporterReadOnlyTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Rig {
        let importer: WorkoutImporter
        let source: FakeWorkoutSource
        let store: SQLiteStore
        let suite: String
        let start: UTCInstant

        /// Anchor guardado, leído de la misma suite (UserDefaults comparte almacenamiento por nombre).
        var savedAnchor: Data? { UserDefaults(suiteName: suite)?.data(forKey: WorkoutImporter.Keys.anchor) }
    }

    private func rig(workouts: [String], anchor: Data? = Data([1]), savedAnchor: Data? = nil) throws -> Rig {
        let dir = FileManager.default.temporaryDirectory.appending(path: "WorkoutImporterReadOnly-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try SQLiteStore(path: dir.appending(path: "store.sqlite").path(percentEncoded: false))
        let start = UTCInstant(Self.now.addingTimeInterval(-7_200))
        let summaries = workouts.map {
            WorkoutSummary(uuid: "w-\($0)", activityName: "Correr", start: start, end: start.adding(seconds: 1_800),
                           durationMin: 30, activeEnergyKcal: 300)
        }
        let source = FakeWorkoutSource(workouts: summaries, anchor: anchor)
        let suite = "WorkoutImporterReadOnly-\(UUID().uuidString)"
        if let savedAnchor { UserDefaults(suiteName: suite)?.set(savedAnchor, forKey: WorkoutImporter.Keys.anchor) }
        let importer = WorkoutImporter(source: source, store: store, defaults: UserDefaults(suiteName: suite)!, now: { Self.now })
        return Rig(importer: importer, source: source, store: store, suite: suite, start: start)
    }

    @Test func importingOnlyReadsFromTheSource() async throws {
        let r = try rig(workouts: ["a", "b"])
        _ = try await r.importer.importNew()
        _ = try await r.importer.importNew()
        #expect(r.source.reads == 2)
        #expect(r.source.nonReadCalls == 0, "el importador no pide permisos ni escribe: solo lee")
    }

    @Test func workoutDeletedInHealthLeavesTheEventUntouched() async throws {
        let r = try rig(workouts: ["a", "b"])
        _ = try await r.importer.importNew()
        let before = try await r.store.events(in: r.start...r.start)
        #expect(before.count == 2)

        r.source.setWorkouts([])   // Salud ya no devuelve ninguno (borrados allí)
        let report = try await r.importer.importNew()
        #expect(report == WorkoutImportReport(imported: 0, updated: 0, unchanged: 0))
        let after = try await r.store.events(in: r.start...r.start)
        #expect(after == before, "ni se borra ni se edita el evento del diario")
        #expect(after.allSatisfy { !$0.deleted && $0.revision == 1 })
        #expect(await r.importer.status().totalImported == 2)
    }

    @Test func anchorIsNotSavedWithoutPermissionAndTheWindowIsKept() async throws {
        let r = try rig(workouts: [])   // sin permiso Salud devuelve lista vacía sin error
        let report = try await r.importer.importNew()
        #expect(report == WorkoutImportReport())
        #expect(r.savedAnchor == nil)
        _ = try await r.importer.importNew()
        #expect(r.source.anchorsSeen.count == 2 && r.source.anchorsSeen.allSatisfy { $0 == nil },
                "sigue mirando la ventana de 30 días")

        // Llega el permiso: aparecen entrenamientos antiguos y ahora sí se guarda el anchor.
        let start = r.start
        r.source.setWorkouts([WorkoutSummary(uuid: "w-old", activityName: "Caminar", start: start, end: start.adding(seconds: 600),
                                             durationMin: 10)])
        #expect(try await r.importer.importNew().imported == 1)
        #expect(r.savedAnchor == Data([1]))
    }

    @Test func existingAnchorIsKeptUpdatedEvenWhenNothingIsNew() async throws {
        let r = try rig(workouts: [], anchor: Data([7]), savedAnchor: Data([3]))
        _ = try await r.importer.importNew()
        #expect(r.source.anchorsSeen == [Data([3])], "usa el anchor guardado")
        #expect(r.savedAnchor == Data([7]))
    }

    @Test func missingAnchorFromTheSourceNeverClearsTheSavedOne() async throws {
        let r = try rig(workouts: [], anchor: nil, savedAnchor: Data([3]))
        _ = try await r.importer.importNew()
        #expect(r.savedAnchor == Data([3]))
    }
}
