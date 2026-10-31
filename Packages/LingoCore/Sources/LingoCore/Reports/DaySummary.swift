/// Mini-estadísticas de un día local (cobertura medida sobre la parte del día dentro del período).
/// Un día "tiene datos" si `stats.meetsDayCoverage` (≥ `ReportThresholds.minimumDayCoverage`).
public struct DaySummary: Sendable, Hashable, Codable {
    public let day: LocalDay
    public let stats: GlucoseStats

    public init(day: LocalDay, stats: GlucoseStats) {
        self.day = day
        self.stats = stats
    }

    public var hasEnoughData: Bool { stats.meetsDayCoverage }
}
