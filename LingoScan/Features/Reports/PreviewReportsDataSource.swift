import LingoCore

/// Fuente sintética de Reportes: la sesión actual de `PreviewData` (3 días) más su historial de 11 días.
/// Deja fuera los vectores de Juggluco (tramas sueltas de otra sesión). El historial se genera una vez, al primer uso.
actor PreviewReportsDataSource: ReportsDataSource {
    private let data: PreviewData
    private var cached: (readings: [GlucoseReading], events: [DiaryEvent])?

    init(data: PreviewData) {
        self.data = data
    }

    nonisolated var isSynthetic: Bool { true }

    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading] {
        all().readings.filter { range.contains($0.measuredAt) }
    }

    func events(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent] {
        all().events.filter { range.contains($0.at) }
    }

    private func all() -> (readings: [GlucoseReading], events: [DiaryEvent]) {
        if let cached { return cached }
        let history = data.reportHistory()
        let current = data.readings.filter { $0.sessionID == data.session.sessionID }
        let result = (history.readings + current, history.events + data.events)
        cached = result
        return result
    }
}
