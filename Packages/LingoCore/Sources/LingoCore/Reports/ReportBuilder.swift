import Foundation
import Synchronization

/// Fachada del motor de reportes (T-27a). Puro, determinista, sin E/S ni reloj: todo entra por parámetros.
///
/// Uso típico desde la app:
/// ```swift
/// let period = ReportPeriod.preset(.days14, endingAt: UTCInstant(Date()), timeZone: .current)
/// let readings = try await store.readings(in: period.dataRange)
/// let events = try await store.events(in: period.dataRange)   // o la consulta de eventos equivalente
/// let bundle = ReportBuilder.build(readings: readings, events: events, period: period,
///                                  configuration: ReportConfiguration(range: userRange))
/// let json = try bundle.snapshot.compact().jsonData()
/// ```
/// Las lecturas fuera del período solo se usan para la semana anterior de `WeeklyComparisonReport` y para líneas
/// base de comidas o ejercicios que empiezan al inicio del período.
public enum ReportBuilder {
    /// Desde lecturas completas: solo glucosa, no borradas, elegibles y con valor (como `BasicStats`).
    /// Las sintéticas cuentan, igual que en `BasicStats` (sesiones de demostración del simulador).
    /// Eventos: solo `meal` y `exercise` no borrados; las notas y el texto libre se ignoran.
    public static func build(
        readings: [GlucoseReading],
        events: [DiaryEvent],
        period: ReportPeriod,
        configuration: ReportConfiguration = .default
    ) -> ReportBundle {
        let samples = readings.compactMap { reading -> BasicStats.Sample? in
            guard reading.analyte == .glucose, !reading.deleted, reading.eligibility.isEligible, let value = reading.value
            else { return nil }
            return BasicStats.Sample(measuredAt: reading.measuredAt, valueMgdl: value)
        }
        return build(samples: samples, events: events, period: period, configuration: configuration)
    }

    /// Desde lecturas válidas ya filtradas. El orden da igual; las repetidas del mismo instante cuentan una vez.
    public static func build(
        samples: [BasicStats.Sample],
        events: [DiaryEvent],
        period: ReportPeriod,
        configuration: ReportConfiguration = .default
    ) -> ReportBundle {
        let context = ReportContext(samples: samples, events: events, period: period, configuration: configuration)
        let summary = PeriodSummaryReport(context: context)
        let interval = context.days.count <= ReportBundle.fineSeriesMaxDays ? 5 : 15
        // Los reportes son independientes entre sí: se calculan en paralelo y se ensamblan en orden fijo.
        let parts = Mutex(Parts())
        DispatchQueue.concurrentPerform(iterations: 8) { job in
            switch job {
            case 0: let r = HourlyProfileReport(context: context); parts.withLock { $0.hourly = r }
            case 1: let r = DailyOverlayReport(context: context, summaries: summary.days); parts.withLock { $0.overlay = r }
            case 2: let r = WeeklyComparisonReport(context: context); parts.withLock { $0.weekly = r }
            case 3: let r = MealResponseReport(context: context); parts.withLock { $0.meals = r }
            case 4: let r = NightReport(context: context); parts.withLock { $0.nights = r }
            case 5: let r = ExerciseEffectReport(context: context); parts.withLock { $0.exercise = r }
            case 6: let r = TimeOfDayPatternsReport(context: context); parts.withLock { $0.timeOfDay = r }
            default:
                let r = ResampledSeries.make(times: context.times[context.periodRange],
                                             values: context.values[context.periodRange],
                                             start: period.start, end: period.end, intervalMinutes: interval)
                parts.withLock { $0.series = r }
            }
        }
        return parts.withLock { p in
            ReportBundle(
                period: period, configuration: configuration, summary: summary,
                hourlyProfile: p.hourly!, dailyOverlay: p.overlay!, weeklyComparison: p.weekly!, meals: p.meals!,
                nights: p.nights!, exercise: p.exercise!, timeOfDay: p.timeOfDay!, series: p.series!)
        }
    }

    private struct Parts {
        var hourly: HourlyProfileReport?
        var overlay: DailyOverlayReport?
        var weekly: WeeklyComparisonReport?
        var meals: MealResponseReport?
        var nights: NightReport?
        var exercise: ExerciseEffectReport?
        var timeOfDay: TimeOfDayPatternsReport?
        var series: ResampledSeries?
    }
}
