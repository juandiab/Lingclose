import LingoCore

/// Los reportes que el análisis puede comentar (uno por sección de la respuesta), con el mismo nombre que las
/// claves del `ReportSnapshot`. Un reporte sin datos suficientes (`hasEnoughData`) no se pide a la IA.
enum ReportAnalysisTopic: String, Sendable, CaseIterable, Hashable {
    case summary
    case hourlyProfile = "hourly_profile"
    case weeklyComparison = "weekly_comparison"
    case meals
    case nights
    case exercise
    case timeOfDay = "time_of_day"

    /// ¿Tiene el reporte los mínimos de datos documentados en `ReportThresholds`?
    func hasEnoughData(in bundle: ReportBundle) -> Bool {
        switch self {
        case .summary: bundle.summary.hasEnoughData
        case .hourlyProfile: bundle.hourlyProfile.hasEnoughData
        case .weeklyComparison: bundle.weeklyComparison.hasEnoughData
        case .meals: bundle.meals.hasEnoughData
        case .nights: bundle.nights.hasEnoughData
        case .exercise: bundle.exercise.hasEnoughData
        case .timeOfDay: bundle.timeOfDay.hasEnoughData
        }
    }
}
