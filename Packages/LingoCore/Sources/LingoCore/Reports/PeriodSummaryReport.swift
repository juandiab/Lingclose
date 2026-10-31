/// Reporte 1 — resumen del período (T-27a). Informativo, no médico.
///
/// - `stats`: tiempo por banda, media, SD, CV, lecturas y cobertura de todo el período.
/// - Huecos: separaciones entre lecturas válidas contiguas, o entre los bordes del período y la primera/última
///   lectura, mayores que `ReportThresholds.gapSeconds` (10 min). `gapMinutes` suma la duración completa de
///   cada hueco. Sin lecturas, todo el período es un hueco.
/// - `days`: mini-estadísticas por día local; un día con cobertura < 50 % se lista pero no cuenta en
///   `daysWithData`.
/// Mínimo para considerarlo con datos: `daysWithData ≥ 1`.
public struct PeriodSummaryReport: Sendable, Hashable, Codable {
    public let stats: GlucoseStats
    public let gaps: Int
    public let gapMinutes: Int
    public let longestGapMinutes: Int
    public let daysWithData: Int
    public internal(set) var days: [DaySummary]

    public var hasEnoughData: Bool { daysWithData >= 1 }

    enum CodingKeys: String, CodingKey {
        case stats, gaps
        case gapMinutes = "gap_minutes"
        case longestGapMinutes = "longest_gap_minutes"
        case daysWithData = "days_with_data"
        case days
    }

    init(context: ReportContext) {
        let period = context.period
        stats = context.stats(context.periodRange, windowSeconds: period.durationSeconds)

        var gaps = 0, gapSeconds: Int64 = 0, longest: Int64 = 0
        func see(_ dt: Int64) {
            guard dt > ReportThresholds.gapSeconds else { return }
            gaps += 1
            gapSeconds += dt
            longest = max(longest, dt)
        }
        var previous = period.start.epochSeconds
        for index in context.periodRange {
            see(context.times[index] - previous)
            previous = context.times[index]
        }
        see(period.end.epochSeconds - previous)
        self.gaps = gaps
        gapMinutes = Int(gapSeconds / 60)
        longestGapMinutes = Int(longest / 60)

        days = context.days.map { day in
            let from = max(day.start, period.start).epochSeconds
            let to = min(day.end, period.end).epochSeconds
            return DaySummary(day: day, stats: context.stats(context.range(from: from, to: to), windowSeconds: to - from))
        }
        daysWithData = days.filter(\.hasEnoughData).count
    }
}
