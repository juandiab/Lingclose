import Foundation
import Synchronization

/// Datos preparados una sola vez para los siete reportes: lecturas válidas ordenadas y sin repetidos, su hora
/// local, los días del período y los eventos del diario. Interno y sin estado compartido.
struct ReportContext {
    let period: ReportPeriod
    let configuration: ReportConfiguration
    let calendar: Calendar
    let clock: LocalClock
    /// Todas las lecturas recibidas (también fuera del período), ordenadas, una por instante.
    let times: [Int64]
    let values: [Int]
    /// Segundos de reloj local de cada lectura.
    let localSeconds: [Int64]
    /// Índices de las lecturas dentro de `[period.start, period.end)`.
    let periodRange: Range<Int>
    let days: [LocalDay]
    let dayNumbers: [Int64]
    /// Comidas y ejercicios no borrados, ordenados por hora (todos los recibidos).
    let allMeals: [DiaryEvent]
    let allExercises: [DiaryEvent]
    /// Cambios rápidos (`RateOfChange.events`) de las lecturas del período.
    let rateEvents: [RateEvent]

    init(samples: [BasicStats.Sample], events: [DiaryEvent], period: ReportPeriod, configuration: ReportConfiguration) {
        self.period = period
        self.configuration = configuration
        calendar = ReportPeriod.calendar(period.timeZone)

        // Orden determinista: por instante y, en empate, por valor; se queda el primero de cada instante.
        let sorted = samples.sorted {
            $0.measuredAt != $1.measuredAt ? $0.measuredAt < $1.measuredAt : $0.valueMgdl < $1.valueMgdl
        }
        var times: [Int64] = []
        var values: [Int] = []
        times.reserveCapacity(sorted.count)
        values.reserveCapacity(sorted.count)
        for sample in sorted where times.last != sample.measuredAt.epochSeconds {
            times.append(sample.measuredAt.epochSeconds)
            values.append(sample.valueMgdl)
        }
        self.times = times
        self.values = values

        let from = min(times.first ?? period.start.epochSeconds, period.dataStart.epochSeconds) - 2 * 86_400
        let to = max(times.last ?? period.end.epochSeconds, period.end.epochSeconds) + 2 * 86_400
        let clock = LocalClock(timeZone: period.timeZone, from: from, to: to)
        self.clock = clock
        localSeconds = times.map { clock.localSeconds($0) }

        let lower = Self.lowerBound(times, period.start.epochSeconds)
        let upper = Self.lowerBound(times, period.end.epochSeconds)
        periodRange = lower..<max(lower, upper)

        if period.end > period.start {
            let first = clock.dayNumber(period.start.epochSeconds)
            let last = clock.dayNumber(period.end.epochSeconds - 1)
            dayNumbers = first <= last ? Array(first...last) : []
        } else {
            dayNumbers = []
        }
        let calendar = self.calendar
        days = dayNumbers.map { LocalDay.make(number: $0, calendar: calendar, clock: clock) }

        let live = events.filter { !$0.deleted }.sorted {
            $0.at != $1.at ? $0.at < $1.at : $0.eventID < $1.eventID
        }
        allMeals = live.filter { $0.kind == .meal }
        allExercises = live.filter { $0.kind == .exercise }

        rateEvents = Self.rateEvents(times: times, values: values, periodRange: periodRange,
                                     cores: days.map { (max($0.start, period.start).epochSeconds, min($0.end, period.end).epochSeconds) },
                                     threshold: configuration.fastChangeThreshold)
    }

    /// Margen a cada lado de un día al buscar cambios rápidos por trozos (segundos).
    static let rateChunkMargin: Int64 = 2 * 3_600

    /// `RateOfChange.events` sobre las lecturas del período, calculado por días locales en paralelo: cada día se
    /// procesa con 2 h de margen a cada lado y se queda con los episodios que **empiezan** en él. Es idéntico al
    /// cálculo de una sola pasada salvo para episodios que cruzan la medianoche y duran más de 2 h (≥ 240 mg/dL de subida o bajada continua a ≥ 2 mg/dL/min).
    /// Determinista: el resultado se ordena por inicio.
    static func rateEvents(times: [Int64], values: [Int], periodRange: Range<Int>, cores: [(Int64, Int64)],
                           threshold: Double) -> [RateEvent] {
        guard !periodRange.isEmpty, !cores.isEmpty else { return [] }
        let first = times[periodRange.lowerBound], last = times[periodRange.upperBound - 1]
        let results = Mutex([[RateEvent]](repeating: [], count: cores.count))
        DispatchQueue.concurrentPerform(iterations: cores.count) { k in
            let (coreStart, coreEnd) = cores[k]
            guard coreEnd > coreStart, coreEnd > first, coreStart <= last else { return }
            let lower = max(periodRange.lowerBound, lowerBound(times, coreStart - rateChunkMargin))
            let upper = min(periodRange.upperBound, lowerBound(times, coreEnd + rateChunkMargin))
            guard upper > lower else { return }
            let samples = (lower..<upper).map {
                BasicStats.Sample(measuredAt: UTCInstant(epochSeconds: times[$0]), valueMgdl: values[$0])
            }
            let found = RateOfChange.events(in: samples, threshold: threshold)
                .filter { $0.start.epochSeconds >= coreStart && $0.start.epochSeconds < coreEnd }
            results.withLock { $0[k] = found }
        }
        return results.withLock { $0.flatMap { $0 } }.sorted { $0.start < $1.start }
    }

    var meals: [DiaryEvent] { allMeals.filter { period.contains($0.at) } }
    var exercises: [DiaryEvent] { allExercises.filter { period.contains($0.at) } }

    /// Índices de las lecturas en `[from, to)`.
    func range(from: Int64, to: Int64) -> Range<Int> {
        let lower = Self.lowerBound(times, from)
        return lower..<max(lower, Self.lowerBound(times, to))
    }

    func samples(_ range: Range<Int>) -> [BasicStats.Sample] {
        range.map { BasicStats.Sample(measuredAt: UTCInstant(epochSeconds: times[$0]), valueMgdl: values[$0]) }
    }

    func stats(_ range: Range<Int>, windowSeconds: Int64?) -> GlucoseStats {
        var accumulator = GlucoseStats.Accumulator(configuration: configuration)
        for index in range { accumulator.add(time: times[index], value: values[index]) }
        return accumulator.stats(windowSeconds: windowSeconds)
    }

    /// Día local número `number` (puede estar fuera del período).
    func localDay(number: Int64) -> LocalDay { LocalDay.make(number: number, calendar: calendar, clock: clock) }

    /// Lectura más cercana a `target` a `≤ tolerance` segundos.
    func value(near target: Int64, tolerance: Int64 = ReportThresholds.pointToleranceSeconds) -> Int? {
        let r = range(from: target - tolerance, to: target + tolerance + 1)
        return r.min { abs(times[$0] - target) < abs(times[$1] - target) }.map { values[$0] }
    }

    /// Minuto local `minute` del día que empieza en `dayStart` (hora de reloj, respeta cambios de horario).
    func instant(onDayStarting dayStart: UTCInstant, minute: Int) -> UTCInstant {
        let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: dayStart.date)
            ?? dayStart.date.addingTimeInterval(TimeInterval(minute * 60))
        return UTCInstant(date)
    }

    static func lowerBound(_ array: [Int64], _ value: Int64) -> Int {
        var low = 0, high = array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
