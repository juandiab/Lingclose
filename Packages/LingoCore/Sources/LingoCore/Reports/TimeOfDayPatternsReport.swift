/// Reporte 7 — patrones por franja del día (T-27a). Informativo, no médico.
///
/// Cuatro franjas de reloj local (`TimeOfDaySlot`: 6–11, 11–16, 16–22, 22–6) con todas las lecturas del período:
/// estadísticas (media, TIR…) y cambios rápidos de `RateOfChange.events` (umbral `fastChangeThreshold`) asignados
/// a la franja de su inicio. `coverage` es aproximada: minutos con lectura / (minutos de la franja × días del período).
/// Mínimo: con lecturas de menos de `ReportThresholds.minimumDaysPerTimeSlot` (3) días distintos, la franja no es
/// fiable y sus frecuencias por día (`fastRisesPerDay`, `fastFallsPerDay`) son `nil`.
public struct TimeOfDayPatternsReport: Sendable, Hashable, Codable {
    public struct Slot: Sendable, Hashable, Codable {
        public let slot: TimeOfDaySlot
        public let stats: GlucoseStats
        public let days: Int
        public let fastRises: Int
        public let fastFalls: Int
        public let fastRisesPerDay: Double?
        public let fastFallsPerDay: Double?

        public var isReliable: Bool { days >= ReportThresholds.minimumDaysPerTimeSlot }

        enum CodingKeys: String, CodingKey {
            case slot, stats, days
            case fastRises = "fast_rises"
            case fastFalls = "fast_falls"
            case fastRisesPerDay = "fast_rises_per_day"
            case fastFallsPerDay = "fast_falls_per_day"
        }
    }

    public let slots: [Slot]

    public var hasEnoughData: Bool { slots.contains(where: \.isReliable) }

    init(context: ReportContext) {
        let all = TimeOfDaySlot.allCases
        var accumulators = all.map { _ in GlucoseStats.Accumulator(configuration: context.configuration) }
        // Días distintos por franja (mismo argumento que en `HourlyProfileReport`: el día local no retrocede).
        var days = [Int](repeating: 0, count: all.count)
        var lastDay = [Int64](repeating: .min, count: all.count)
        func position(_ slot: TimeOfDaySlot) -> Int { all.firstIndex(of: slot) ?? 0 }
        for index in context.periodRange {
            let local = context.localSeconds[index]
            let k = position(TimeOfDaySlot(minuteOfDay: LocalClock.minuteOfDay(localSeconds: local)))
            accumulators[k].add(time: context.times[index], value: context.values[index])
            let day = LocalClock.dayNumber(localSeconds: local)
            if day != lastDay[k] {
                days[k] += 1
                lastDay[k] = day
            }
        }
        var rises = [Int](repeating: 0, count: all.count)
        var falls = [Int](repeating: 0, count: all.count)
        for event in context.rateEvents {
            let k = position(TimeOfDaySlot(minuteOfDay: context.clock.minuteOfDay(event.start.epochSeconds)))
            if event.direction == .rising { rises[k] += 1 } else { falls[k] += 1 }
        }
        let periodDays = Int64(context.days.count)
        slots = all.indices.map { k in
            let slot = all[k]
            let reliable = days[k] >= ReportThresholds.minimumDaysPerTimeSlot
            let n = Double(days[k])
            return Slot(
                slot: slot,
                stats: accumulators[k].stats(windowSeconds: Int64(slot.lengthMinutes) * 60 * periodDays),
                days: days[k], fastRises: rises[k], fastFalls: falls[k],
                fastRisesPerDay: reliable ? ReportRounding.r3(Double(rises[k]) / n) : nil,
                fastFallsPerDay: reliable ? ReportRounding.r3(Double(falls[k]) / n) : nil)
        }
    }
}
