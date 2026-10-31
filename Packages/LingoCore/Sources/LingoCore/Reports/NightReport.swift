/// Reporte 5 — noches (T-27a). Informativo, no médico.
///
/// Una noche por día local en que empieza la ventana (`nightStartMinute`→`nightEndMinute`, por defecto
/// 23:00–07:00, hora de reloj), recortada al período para tomar lecturas; las que quedan fuera no se listan.
/// Por noche: estadísticas, mediana (línea base nocturna), mínimo y su hora, episodios bajos (≥ 15 min seguidos
/// bajo `rangeLow`, huecos ≤ 5 min) y cambios rápidos (`RateOfChange.events` que empiezan en la ventana).
/// Mínimo: una noche es fiable si su cobertura sobre la ventana **completa** es ≥ 70 %
/// (`ReportThresholds.minimumNightCoverage`), así una noche a medias no lo es; las no fiables se listan pero no
/// entran en `summary`, que necesita ≥ `ReportThresholds.minimumNightsForSummary` (3) noches fiables.
public struct NightReport: Sendable, Hashable, Codable {
    public struct Night: Sendable, Hashable, Codable {
        /// Fecha local (`YYYY-MM-DD`) del día en que empieza la noche.
        public let night: String
        public let start: UTCInstant
        public let end: UTCInstant
        public let stats: GlucoseStats
        public let median: Double?
        public let minimumAt: UTCInstant?
        public let lowEpisodes: Int
        public let fastFalls: Int
        public let fastRises: Int

        public var isReliable: Bool { (stats.coverage ?? 0) >= ReportThresholds.minimumNightCoverage }

        enum CodingKeys: String, CodingKey {
            case night, start, end, stats, median
            case minimumAt = "min_at"
            case lowEpisodes = "low_episodes"
            case fastFalls = "fast_falls"
            case fastRises = "fast_rises"
        }
    }

    public struct Summary: Sendable, Hashable, Codable {
        public let nights: Int
        public let reliableNights: Int
        public let medianOfMedians: Double?
        public let meanMinimum: Double?
        public let meanStandardDeviation: Double?
        public let meanTimeInRange: Double?
        public let nightsWithLowEpisode: Int?
        public let fastFalls: Int?

        public var isReliable: Bool { reliableNights >= ReportThresholds.minimumNightsForSummary }

        enum CodingKeys: String, CodingKey {
            case nights
            case reliableNights = "reliable_nights"
            case medianOfMedians = "median_of_medians"
            case meanMinimum = "mean_min"
            case meanStandardDeviation = "mean_sd"
            case meanTimeInRange = "mean_time_in_range"
            case nightsWithLowEpisode = "nights_with_low_episode"
            case fastFalls = "fast_falls"
        }
    }

    public internal(set) var nights: [Night]
    public let summary: Summary

    public var hasEnoughData: Bool { summary.isReliable }

    enum CodingKeys: String, CodingKey {
        case nights, summary
    }

    init(context: ReportContext) {
        let config = context.configuration
        let period = context.period
        var result: [Night] = []
        if let first = context.dayNumbers.first, let last = context.dayNumbers.last {
            let crossesMidnight = config.nightStartMinute > config.nightEndMinute
            for number in (first - 1)...last {
                let day = context.localDay(number: number)
                let start = context.instant(onDayStarting: day.start, minute: config.nightStartMinute)
                let endDay = crossesMidnight ? day.end : day.start
                let end = context.instant(onDayStarting: endDay, minute: config.nightEndMinute)
                let from = max(start, period.start).epochSeconds
                let to = min(end, period.end).epochSeconds
                guard end > start, to > from else { continue }
                let range = context.range(from: from, to: to)
                let stats = context.stats(range, windowSeconds: end.epochSeconds - start.epochSeconds)
                let minimumIndex = range.min { context.values[$0] < context.values[$1] }
                let rates = context.rateEvents.filter { $0.start.epochSeconds >= from && $0.start.epochSeconds < to }
                result.append(Night(
                    night: day.date, start: start, end: end, stats: stats,
                    median: ReportRounding.r1(optional: GlucoseDistribution(samples: context.samples(range)).median),
                    minimumAt: minimumIndex.map { UTCInstant(epochSeconds: context.times[$0]) },
                    lowEpisodes: Self.lowEpisodes(context, range),
                    fastFalls: rates.filter { $0.direction == .falling }.count,
                    fastRises: rates.filter { $0.direction == .rising }.count))
            }
        }
        nights = result
        let reliable = result.filter(\.isReliable)
        let ok = reliable.count >= ReportThresholds.minimumNightsForSummary
        summary = Summary(
            nights: result.count, reliableNights: reliable.count,
            medianOfMedians: ok ? ReportRounding.r1(optional: ReportRounding.median(reliable.compactMap(\.median))) : nil,
            meanMinimum: ok ? ReportRounding.r1(optional: ReportRounding.mean(reliable.compactMap { $0.stats.minimum.map(Double.init) })) : nil,
            meanStandardDeviation: ok ? ReportRounding.r1(optional: ReportRounding.mean(reliable.compactMap(\.stats.standardDeviation))) : nil,
            meanTimeInRange: ok ? ReportRounding.r3(optional: ReportRounding.mean(reliable.compactMap(\.stats.timeInRange))) : nil,
            nightsWithLowEpisode: ok ? reliable.filter { $0.lowEpisodes > 0 }.count : nil,
            fastFalls: ok ? reliable.reduce(0) { $0 + $1.fastFalls } : nil)
    }

    /// Tramos de lecturas `< rangeLow` contiguas (huecos ≤ 5 min) que duran ≥ 15 min.
    static func lowEpisodes(_ context: ReportContext, _ range: Range<Int>) -> Int {
        let low = context.configuration.rangeLow
        var episodes = 0
        var runStart: Int64?
        var runLast: Int64 = 0
        func close() {
            if let s = runStart, runLast - s >= ReportThresholds.lowEpisodeSeconds { episodes += 1 }
            runStart = nil
        }
        for index in range {
            let t = context.times[index]
            if context.values[index] < low {
                if runStart != nil, t - runLast > ReportThresholds.lowEpisodeMaxGapSeconds { close() }
                if runStart == nil { runStart = t }
                runLast = t
            } else {
                close()
            }
        }
        close()
        return episodes
    }
}
