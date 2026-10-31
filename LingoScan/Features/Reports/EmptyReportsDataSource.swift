import LingoCore

/// Fuente sin datos: estados vacíos (previsualizaciones y pruebas) y el arranque provisional sin modelo inyectado.
struct EmptyReportsDataSource: ReportsDataSource {
    var isSynthetic: Bool { false }

    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading] { [] }

    func events(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent] { [] }
}
