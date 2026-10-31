/// Reporte 3a — días superpuestos (T-27a). Informativo, no médico.
///
/// Por cada día local del período: sus estadísticas (`DaySummary`) y una serie de 288 ranuras de 5 min de reloj
/// local (`values[k]` = media redondeada de las lecturas con minuto local en `[5k, 5k + 5)`, `nil` sin lecturas).
/// En el día de 25 h la hora repetida se promedia en la misma ranura; en el de 23 h la hora saltada queda `nil`.
/// Mínimo: un día solo se dibuja como completo si `summary.hasEnoughData` (cobertura ≥ 50 %).
public struct DailyOverlayReport: Sendable, Hashable, Codable {
    public static let slotMinutes = 5
    public static let slotCount = 1440 / 5

    public struct Day: Sendable, Hashable, Codable {
        public let summary: DaySummary
        public let values: [Int?]
    }

    public let days: [Day]

    public var hasEnoughData: Bool { days.contains { $0.summary.hasEnoughData } }

    init(context: ReportContext, summaries: [DaySummary]) {
        var result: [Day] = []
        result.reserveCapacity(summaries.count)
        for summary in summaries {
            let from = max(summary.day.start, context.period.start).epochSeconds
            let to = min(summary.day.end, context.period.end).epochSeconds
            var sums = [Int](repeating: 0, count: Self.slotCount)
            var counts = [Int](repeating: 0, count: Self.slotCount)
            for index in context.range(from: from, to: to) {
                let slot = LocalClock.minuteOfDay(localSeconds: context.localSeconds[index]) / Self.slotMinutes
                sums[slot] += context.values[index]
                counts[slot] += 1
            }
            let values: [Int?] = (0..<Self.slotCount).map {
                counts[$0] == 0 ? nil : Int((Double(sums[$0]) / Double(counts[$0])).rounded())
            }
            result.append(Day(summary: summary, values: values))
        }
        days = result
    }
}
