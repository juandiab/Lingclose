import Foundation

/// Instantánea de los reportes para la IA y para compartir (T-27a): JSON estable con claves snake_case.
///
/// Contiene los siete reportes en números (sin `daily_overlay`, que la serie ya cubre), la serie remuestreada,
/// y por comida/ejercicio solo hora, carbohidratos o duración y la respuesta. **No** contiene texto libre de
/// eventos, ids de eventos o sesiones, seriales, nombres ni la zona horaria por nombre (solo su desfase).
/// `jsonData()` ordena las claves, así que el mismo snapshot da siempre los mismos bytes.
public struct ReportSnapshot: Sendable, Hashable, Codable {
    public static let currentFormatVersion = 1
    /// Tamaño objetivo de `compact()` (≈ 60 KB).
    public static let defaultMaxBytes = 60_000
    /// En `compact`, lo que se conserva al recortar detalles.
    public static let trimmedDays = 14
    public static let trimmedMeals = 30
    public static let trimmedNights = 14
    public static let trimmedExercise = 20

    /// Cuánto se redujo el snapshot para caber (en orden de aplicación).
    public enum Compaction: String, Sendable, Hashable, Codable, CaseIterable {
        case none
        /// La serie pasó a 30 o 60 min.
        case seriesDownsampled = "series_downsampled"
        /// Solo los últimos días, comidas, noches y ejercicios (los agregados siguen siendo de todo el período).
        case detailsTrimmed = "details_trimmed"
        /// Sin serie.
        case seriesRemoved = "series_removed"
        /// Sin listas por día, comida, noche ni ejercicio; solo agregados.
        case detailsRemoved = "details_removed"
    }

    public struct Period: Sendable, Hashable, Codable {
        public let start: UTCInstant
        public let end: UTCInstant
        public let days: Int
        /// Desfase de la zona del período respecto a UTC en `end`, en minutos.
        public let utcOffsetMinutes: Int

        enum CodingKeys: String, CodingKey {
            case start, end, days
            case utcOffsetMinutes = "utc_offset_minutes"
        }
    }

    public let formatVersion: Int
    public let period: Period
    public let configuration: ReportConfiguration
    public private(set) var summary: PeriodSummaryReport
    public let hourlyProfile: HourlyProfileReport
    public let weeklyComparison: WeeklyComparisonReport
    public private(set) var meals: MealResponseReport
    public private(set) var nights: NightReport
    public private(set) var exercise: ExerciseEffectReport
    public let timeOfDay: TimeOfDayPatternsReport
    public private(set) var series: ResampledSeries?
    public private(set) var compaction: Compaction

    public init(bundle: ReportBundle) {
        formatVersion = Self.currentFormatVersion
        period = Period(start: bundle.period.start, end: bundle.period.end, days: bundle.dayCount,
                        utcOffsetMinutes: bundle.period.timeZone.secondsFromGMT(for: bundle.period.end.date) / 60)
        configuration = bundle.configuration
        summary = bundle.summary
        hourlyProfile = bundle.hourlyProfile
        weeklyComparison = bundle.weeklyComparison
        meals = bundle.meals
        nights = bundle.nights
        exercise = bundle.exercise
        timeOfDay = bundle.timeOfDay
        series = bundle.series
        compaction = .none
    }

    /// JSON con claves ordenadas y sin escapar `/`.
    public func jsonData() throws -> Data { try Self.encoder.encode(self) }

    public static func decode(_ data: Data) throws -> ReportSnapshot { try JSONDecoder().decode(ReportSnapshot.self, from: data) }

    /// Reduce el snapshot hasta que su JSON quepa en `maxBytes`, por pasos: serie a 30 min, a 60 min; recorte de
    /// listas a los últimos elementos; sin serie; sin listas. Devuelve el primer paso que cabe, o el último si
    /// ninguno cabe (los agregados nunca se quitan).
    public func compact(maxBytes: Int = ReportSnapshot.defaultMaxBytes) -> ReportSnapshot {
        if fits(maxBytes) { return self }
        var candidate = self
        if let series {
            for target in [30, 60] where series.intervalMinutes < target && target % series.intervalMinutes == 0 {
                candidate.series = series.downsampled(by: target / series.intervalMinutes)
                candidate.compaction = .seriesDownsampled
                if candidate.fits(maxBytes) { return candidate }
            }
        }
        candidate.summary.days = Array(candidate.summary.days.suffix(Self.trimmedDays))
        candidate.meals.meals = Array(candidate.meals.meals.suffix(Self.trimmedMeals))
        candidate.nights.nights = Array(candidate.nights.nights.suffix(Self.trimmedNights))
        candidate.exercise.sessions = Array(candidate.exercise.sessions.suffix(Self.trimmedExercise))
        candidate.compaction = .detailsTrimmed
        if candidate.fits(maxBytes) { return candidate }
        candidate.series = nil
        candidate.compaction = .seriesRemoved
        if candidate.fits(maxBytes) { return candidate }
        candidate.summary.days = []
        candidate.meals.meals = []
        candidate.nights.nights = []
        candidate.exercise.sessions = []
        candidate.compaction = .detailsRemoved
        return candidate
    }

    private func fits(_ maxBytes: Int) -> Bool { ((try? jsonData())?.count ?? Int.max) <= maxBytes }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case period, configuration, summary
        case hourlyProfile = "hourly_profile"
        case weeklyComparison = "weekly_comparison"
        case meals, nights, exercise
        case timeOfDay = "time_of_day"
        case series, compaction
    }
}
