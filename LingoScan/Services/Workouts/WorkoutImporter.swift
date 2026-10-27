import Foundation
import LingoCore

/// Importa entrenamientos de Salud como eventos `exercise` (T-21 §5). La primera vez trae los últimos 30 días;
/// después, solo lo nuevo desde el anchor guardado en `UserDefaults`. `workout_links` evita duplicar.
/// Las importaciones se encadenan: nunca corren dos a la vez (si no, ambas podrían crear el mismo evento).
actor WorkoutImporter {
    static let firstImportWindow: TimeInterval = 30 * 86_400
    static let appID = "com.otalvaro.lingoscan"

    enum Keys {
        static let anchor = "com.otalvaro.lingoscan.workouts.anchor"
        static let lastImportAt = "com.otalvaro.lingoscan.workouts.lastImportAt"
        static let lastReport = "com.otalvaro.lingoscan.workouts.lastReport"
    }

    private let source: any WorkoutSource
    private let store: SQLiteStore
    nonisolated(unsafe) private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let newID: @Sendable () -> String
    private let timeZone: @Sendable () -> TimeZone
    private var running: Task<WorkoutImportReport, any Error>?

    init(
        source: any WorkoutSource,
        store: SQLiteStore,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        newID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.source = source
        self.store = store
        self.defaults = defaults
        self.now = now
        self.newID = newID
        self.timeZone = timeZone
    }

    /// Importa lo nuevo. Si hay una importación en curso, espera a que termine y luego hace la suya.
    func importNew() async throws -> WorkoutImportReport {
        let previous = running
        let task = Task { [previous] in
            _ = try? await previous?.value
            return try await self.run()
        }
        running = task
        return try await task.value
    }

    func status() async -> WorkoutImportStatus {
        let report = defaults.data(forKey: Keys.lastReport).flatMap { try? JSONDecoder().decode(WorkoutImportReport.self, from: $0) }
        let at = defaults.object(forKey: Keys.lastImportAt) as? Date
        return WorkoutImportStatus(lastImportAt: at, lastReport: report, totalImported: (try? await store.linkedWorkoutCount()) ?? 0)
    }

    private func run() async throws -> WorkoutImportReport {
        let anchor = defaults.data(forKey: Keys.anchor)
        let batch = try await source.workouts(since: anchor, notBefore: now().addingTimeInterval(-Self.firstImportWindow))
        var report = WorkoutImportReport()
        for workout in batch.workouts {
            let instant = UTCInstant(now())
            if let eventID = try await store.eventID(forWorkoutUUID: workout.uuid),
               let existing = try await store.event(id: eventID) {
                if let edited = WorkoutEventBuilder.update(
                    existing: existing, with: workout, editID: newID(), appID: Self.appID, now: instant) {
                    try await store.upsertEvent(edited)
                    report.updated += 1
                } else {
                    report.unchanged += 1
                }
            } else {
                let event = WorkoutEventBuilder.event(
                    from: workout, eventID: newID(), editID: newID(), tz: timeZone().identifier,
                    appID: Self.appID, now: instant)
                try await store.saveWorkoutEvent(event, workoutUUID: workout.uuid)
                report.imported += 1
            }
        }
        // Sin permiso de lectura Salud devuelve vacío sin error: un anchor tomado así saltaría los entrenamientos
        // antiguos cuando llegue el permiso. Hasta encontrar alguno se sigue mirando la ventana de 30 días.
        if let newAnchor = batch.anchor, anchor != nil || !batch.workouts.isEmpty {
            defaults.set(newAnchor, forKey: Keys.anchor)
        }
        defaults.set(now(), forKey: Keys.lastImportAt)
        if let data = try? JSONEncoder().encode(report) { defaults.set(data, forKey: Keys.lastReport) }
        return report
    }
}
