/// Los siete reportes de un período (T-27a), más la serie remuestreada. Puro y determinista: mismo input,
/// mismo valor. Informativo, no médico.
public struct ReportBundle: Sendable, Hashable, Codable {
    /// Hasta este número de días la serie va a 5 min; por encima, a 15 min.
    public static let fineSeriesMaxDays = 31

    public let period: ReportPeriod
    public let configuration: ReportConfiguration
    public let summary: PeriodSummaryReport
    public let hourlyProfile: HourlyProfileReport
    public let dailyOverlay: DailyOverlayReport
    public let weeklyComparison: WeeklyComparisonReport
    public let meals: MealResponseReport
    public let nights: NightReport
    public let exercise: ExerciseEffectReport
    public let timeOfDay: TimeOfDayPatternsReport
    /// Lecturas del período a 5 min (≤ 31 días) o 15 min.
    public let series: ResampledSeries

    /// Días locales del período (incluido el de hoy aunque esté a medias).
    public var dayCount: Int { summary.days.count }
    public var hasData: Bool { summary.stats.hasReadings }

    public init(period: ReportPeriod, configuration: ReportConfiguration, summary: PeriodSummaryReport,
                hourlyProfile: HourlyProfileReport, dailyOverlay: DailyOverlayReport,
                weeklyComparison: WeeklyComparisonReport, meals: MealResponseReport, nights: NightReport,
                exercise: ExerciseEffectReport, timeOfDay: TimeOfDayPatternsReport, series: ResampledSeries) {
        self.period = period
        self.configuration = configuration
        self.summary = summary
        self.hourlyProfile = hourlyProfile
        self.dailyOverlay = dailyOverlay
        self.weeklyComparison = weeklyComparison
        self.meals = meals
        self.nights = nights
        self.exercise = exercise
        self.timeOfDay = timeOfDay
        self.series = series
    }

    /// Instantánea para la IA y para compartir (sin texto libre, ids, seriales ni nombres).
    public var snapshot: ReportSnapshot { ReportSnapshot(bundle: self) }

    enum CodingKeys: String, CodingKey {
        case period, configuration, summary
        case hourlyProfile = "hourly_profile"
        case dailyOverlay = "daily_overlay"
        case weeklyComparison = "weekly_comparison"
        case meals, nights, exercise
        case timeOfDay = "time_of_day"
        case series
    }
}
