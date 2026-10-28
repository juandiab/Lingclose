import LingoCore

/// Lo que el servicio de alertas lee y escribe de la base: lecturas elegibles y el registro (`event_log`).
protocol AlertDataStore: Sendable {
    /// Lecturas de glucosa elegibles, no borradas y con valor, ordenadas por hora.
    func alertSamples(in range: ClosedRange<UTCInstant>) async throws -> [BasicStats.Sample]
    /// Registra en `event_log` con categoría `alert`.
    func logAlert(_ level: EventLogLevel, _ message: LogMessage) async
    /// Última comida y último ejercicio del diario en el rango, para los consejos (T-25). Tiene implementación por
    /// defecto vacía (`AlertDataStore+Coaching.swift`).
    func coachingActivity(in range: ClosedRange<UTCInstant>) async -> CoachingActivity
}

extension SQLiteStore: AlertDataStore {
    func alertSamples(in range: ClosedRange<UTCInstant>) async throws -> [BasicStats.Sample] {
        try await readings(in: range).compactMap { reading -> BasicStats.Sample? in
            guard reading.analyte == .glucose, !reading.deleted, reading.eligibility.isEligible, let value = reading.value
            else { return nil }
            return BasicStats.Sample(measuredAt: reading.measuredAt, valueMgdl: value)
        }
        .sorted { $0.measuredAt < $1.measuredAt }
    }

    func logAlert(_ level: EventLogLevel, _ message: LogMessage) async {
        try? logEvent(level, category: "alert", message)
    }
}
