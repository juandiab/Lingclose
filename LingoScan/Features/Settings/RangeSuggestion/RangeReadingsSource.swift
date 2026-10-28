import LingoCore

/// Lecturas por rango de tiempo para "Sugerir rango". `SQLiteStore` las sirve sin borradas; las pruebas usan memoria.
protocol RangeReadingsSource: Sendable {
    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading]
}

extension SQLiteStore: RangeReadingsSource {
    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading] {
        try readings(in: range, includeDeleted: false)
    }
}
