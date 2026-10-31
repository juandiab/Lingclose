/// Reporte 3b — semana actual frente a la anterior (T-27a). Informativo, no médico.
///
/// `current` son los 7 días locales que terminan en el último día del período (hasta `period.end`; el día de hoy
/// puede estar a medias) y `previous` los 7 anteriores. Usa todas las lecturas y eventos recibidos, también de
/// antes de `period.start` (por eso `ReportPeriod.dataStart` mira 14 días atrás).
/// Mínimo: una semana es fiable con ≥ `ReportThresholds.minimumDaysPerWeek` (4) días con cobertura ≥ 50 %;
/// `deltas` (actual − anterior) solo existe si las dos lo son.
/// Minutos de ejercicio: suma de `duration_min`; sin duración, 30 min (`ExerciseEffect.defaultDuration`).
public struct WeeklyComparisonReport: Sendable, Hashable, Codable {
    public struct Week: Sendable, Hashable, Codable {
        public let firstDay: String
        public let lastDay: String
        public let start: UTCInstant
        public let end: UTCInstant
        public let stats: GlucoseStats
        public let daysWithData: Int
        public let meals: Int
        public let exerciseSessions: Int
        public let exerciseMinutes: Int

        public var isReliable: Bool { daysWithData >= ReportThresholds.minimumDaysPerWeek }

        enum CodingKeys: String, CodingKey {
            case firstDay = "first_day"
            case lastDay = "last_day"
            case start, end, stats
            case daysWithData = "days_with_data"
            case meals
            case exerciseSessions = "exercise_sessions"
            case exerciseMinutes = "exercise_minutes"
        }
    }

    public struct Deltas: Sendable, Hashable, Codable {
        public let timeInRange: Double?
        public let mean: Double?
        public let standardDeviation: Double?
        public let coefficientOfVariation: Double?
        public let meals: Int
        public let exerciseMinutes: Int

        enum CodingKeys: String, CodingKey {
            case timeInRange = "time_in_range"
            case mean
            case standardDeviation = "sd"
            case coefficientOfVariation = "cv"
            case meals
            case exerciseMinutes = "exercise_minutes"
        }
    }

    public let current: Week?
    public let previous: Week?
    public let deltas: Deltas?

    public var hasEnoughData: Bool { deltas != nil }

    init(context: ReportContext) {
        guard let lastDay = context.dayNumbers.last else {
            current = nil
            previous = nil
            deltas = nil
            return
        }
        let current = Self.week(context, firstDay: lastDay - 6, lastDay: lastDay)
        let previous = Self.week(context, firstDay: lastDay - 13, lastDay: lastDay - 7)
        self.current = current
        self.previous = previous
        if current.isReliable, previous.isReliable {
            func d(_ a: Double?, _ b: Double?, _ round: (Double) -> Double) -> Double? {
                guard let a, let b else { return nil }
                return round(a - b)
            }
            deltas = Deltas(
                timeInRange: d(current.stats.timeInRange, previous.stats.timeInRange, ReportRounding.r3),
                mean: d(current.stats.mean, previous.stats.mean, ReportRounding.r1),
                standardDeviation: d(current.stats.standardDeviation, previous.stats.standardDeviation, ReportRounding.r1),
                coefficientOfVariation: d(current.stats.coefficientOfVariation, previous.stats.coefficientOfVariation, ReportRounding.r3),
                meals: current.meals - previous.meals,
                exerciseMinutes: current.exerciseMinutes - previous.exerciseMinutes)
        } else {
            deltas = nil
        }
    }

    private static func week(_ context: ReportContext, firstDay: Int64, lastDay: Int64) -> Week {
        let days = (firstDay...lastDay).map { context.localDay(number: $0) }
        let start = days[0].start
        let end = min(days[days.count - 1].end, context.period.end)
        let stats = context.stats(context.range(from: start.epochSeconds, to: end.epochSeconds),
                                  windowSeconds: end.epochSeconds - start.epochSeconds)
        let daysWithData = days.filter { day in
            let to = min(day.end, end).epochSeconds
            guard to > day.start.epochSeconds else { return false }
            return context.stats(context.range(from: day.start.epochSeconds, to: to),
                                 windowSeconds: to - day.start.epochSeconds).meetsDayCoverage
        }.count
        let inWeek: (DiaryEvent) -> Bool = { $0.at >= start && $0.at < end }
        let exercises = context.allExercises.filter(inWeek)
        let defaultMinutes = Int(ExerciseEffect.defaultDuration / 60)
        return Week(
            firstDay: days[0].date, lastDay: days[days.count - 1].date, start: start, end: end, stats: stats,
            daysWithData: daysWithData, meals: context.allMeals.filter(inWeek).count,
            exerciseSessions: exercises.count,
            exerciseMinutes: exercises.reduce(0) { $0 + max(0, $1.durationMin ?? defaultMinutes) })
    }
}
