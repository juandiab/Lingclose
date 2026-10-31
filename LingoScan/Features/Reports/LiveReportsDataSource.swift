import LingoCore

/// Fuente real de Reportes sobre `SQLiteStore` (actor): lecturas y eventos del rango `period.dataRange`.
struct LiveReportsDataSource: ReportsDataSource {
    let store: SQLiteStore

    var isSynthetic: Bool { false }

    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading] {
        try await store.readings(in: range)
    }

    func events(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent] {
        try await store.events(in: range)
    }
}
