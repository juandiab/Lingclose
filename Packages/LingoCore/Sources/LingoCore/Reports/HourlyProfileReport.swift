/// Reporte 2 — perfil horario tipo AGP (T-27a). Informativo, no médico.
///
/// 48 bins de 30 min de reloj local (bin `k` = minutos `[30k, 30k + 30)`), con las lecturas de todos los días
/// del período. Percentiles 5/25/50/75/95 con `GlucoseDistribution.percentile` (tipo 7).
/// Mínimo: un bin con lecturas de menos de `ReportThresholds.minimumDaysPerHourlyBin` (3) días locales distintos
/// no se reporta (percentiles `nil`); `readings` y `days` sí se dan siempre.
public struct HourlyProfileReport: Sendable, Hashable, Codable {
    public static let binMinutes = 30
    public static let binCount = 48

    public struct Bin: Sendable, Hashable, Codable {
        public let startMinute: Int
        public let readings: Int
        public let days: Int
        public let p5: Double?
        public let p25: Double?
        public let p50: Double?
        public let p75: Double?
        public let p95: Double?

        public var isReported: Bool { p50 != nil }

        enum CodingKeys: String, CodingKey {
            case startMinute = "start_minute"
            case readings, days, p5, p25, p50, p75, p95
        }
    }

    public let bins: [Bin]

    public var reportedBins: Int { bins.filter(\.isReported).count }
    public var hasEnoughData: Bool { reportedBins > 0 }

    init(context: ReportContext) {
        var samples = [[BasicStats.Sample]](repeating: [], count: Self.binCount)
        // Días distintos por bin: las lecturas llegan en orden y, dentro de un bin, el número de día local nunca
        // retrocede (una hora repetida por cambio de horario es del mismo día), así que basta con el último visto.
        var days = [Int](repeating: 0, count: Self.binCount)
        var lastDay = [Int64](repeating: .min, count: Self.binCount)
        for index in context.periodRange {
            let local = context.localSeconds[index]
            let bin = LocalClock.minuteOfDay(localSeconds: local) / Self.binMinutes
            samples[bin].append(BasicStats.Sample(measuredAt: UTCInstant(epochSeconds: context.times[index]),
                                                  valueMgdl: context.values[index]))
            let day = LocalClock.dayNumber(localSeconds: local)
            if day != lastDay[bin] {
                days[bin] += 1
                lastDay[bin] = day
            }
        }
        bins = (0..<Self.binCount).map { k in
            let reported = days[k] >= ReportThresholds.minimumDaysPerHourlyBin
            let distribution = reported ? GlucoseDistribution(samples: samples[k]) : nil
            func p(_ q: Double) -> Double? { ReportRounding.r1(optional: distribution?.percentile(q)) }
            return Bin(startMinute: k * Self.binMinutes, readings: samples[k].count, days: days[k],
                       p5: p(5), p25: p(25), p50: p(50), p75: p(75), p95: p(95))
        }
    }
}
