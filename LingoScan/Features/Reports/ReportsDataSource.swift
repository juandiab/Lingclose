import LingoCore

/// De dónde salen las lecturas y los eventos de Reportes. El motor (`ReportBuilder`) filtra lo no elegible.
protocol ReportsDataSource: Sendable {
    /// `true` con datos de ejemplo: la pantalla lo rotula.
    var isSynthetic: Bool { get }
    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading]
    func events(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent]
}
