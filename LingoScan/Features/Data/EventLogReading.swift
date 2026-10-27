import LingoCore

/// Lectura del `event_log` para el resumen de errores recientes.
protocol EventLogReading: Sendable {
    func recentLogEvents(limit: Int) async throws -> [EventLogEntry]
}

extension SQLiteStore: EventLogReading {}
