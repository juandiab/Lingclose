import LingoCore
import SwiftUI

/// Contenido de la card de un reporte en la pantalla principal.
struct ReportCardContent: View {
    let route: ReportRoute
    let content: ReportContent

    var body: some View {
        let bundle = content.bundle
        switch route {
        case .summary:
            SummaryCardContent(report: bundle.summary, configuration: content.configuration)
        case .hourlyProfile:
            HourlyProfileCardContent(content: content)
        case .dailyOverlay:
            DailyOverlayCardContent(content: content)
        case .weeklyComparison:
            WeeklyComparisonCardContent(report: bundle.weeklyComparison, configuration: content.configuration)
        case .meals:
            MealsCardContent(content: content)
        case .nights:
            NightsCardContent(report: bundle.nights, configuration: content.configuration)
        case .exercise:
            ExerciseCardContent(report: bundle.exercise)
        case .timeOfDay:
            TimeOfDayCardContent(report: bundle.timeOfDay, daysWithData: bundle.summary.daysWithData)
        }
    }

    /// Subtítulo de la card (contexto que no cabe en el título).
    static func caption(_ route: ReportRoute, content: ReportContent) -> String? {
        switch route {
        case .hourlyProfile:
            String(localized: "reports.profile.caption", defaultValue: "Todos los días apilados en 24 horas")
        case .weeklyComparison:
            String(localized: "reports.weekly.cardCaption", defaultValue: "Últimos 7 días frente a los 7 anteriores")
        case .meals:
            String(localized: "reports.meals.caption", defaultValue: "Las 3 horas después de cada comida")
        case .nights:
            String(localized: "reports.nights.cardCaption", defaultValue: "Noches \(ReportNames.nightWindow(content.configuration))")
        case .summary, .dailyOverlay, .exercise, .timeOfDay:
            nil
        }
    }
}
