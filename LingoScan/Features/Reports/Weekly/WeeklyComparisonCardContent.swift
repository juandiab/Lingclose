import LingoCore
import SwiftUI

/// Card de semana a semana: tabla de glucosa o qué falta (dos semanas con ≥ 4 días de datos).
struct WeeklyComparisonCardContent: View {
    let report: WeeklyComparisonReport
    let configuration: ReportConfiguration
    var metrics = WeeklyMetric.glucose

    var body: some View {
        if report.hasEnoughData {
            WeeklyComparisonTable(report: report, metrics: metrics, configuration: configuration)
        } else {
            ReportEmptyState(message: String(
                localized: "reports.weekly.empty",
                defaultValue: "La comparación necesita dos semanas seguidas con al menos \(ReportThresholds.minimumDaysPerWeek) días de datos cada una. Esta semana: \(report.current?.daysWithData ?? 0) días; la anterior: \(report.previous?.daysWithData ?? 0)."))
        }
    }
}
