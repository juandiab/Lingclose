import LingoCore
import SwiftUI

/// Detalle de semana a semana: todas las métricas y las fechas de cada semana.
struct WeeklyComparisonDetailView: View {
    let content: ReportContent

    var body: some View {
        let report = content.bundle.weeklyComparison
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportCard(
                    title: String(localized: "reports.weekly.title", defaultValue: "Semana a semana"),
                    systemImage: "arrow.left.arrow.right",
                    caption: caption(report)
                ) {
                    WeeklyComparisonCardContent(report: report, configuration: content.configuration, metrics: WeeklyMetric.allCases)
                    Text(String(
                        localized: "reports.weekly.explainer",
                        defaultValue: "Últimos 7 días frente a los 7 anteriores. Verde: el dato se movió hacia más tiempo en rango, menos variabilidad o una media más cerca del centro del rango; ámbar: al revés. Comidas y ejercicio solo se cuentan."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }

    private func caption(_ report: WeeklyComparisonReport) -> String? {
        guard let current = report.current, let previous = report.previous else { return nil }
        return String(
            localized: "reports.weekly.caption",
            defaultValue: "Esta semana: \(ReportFormat.localDate(current.firstDay)) a \(ReportFormat.localDate(current.lastDay)) · anterior: \(ReportFormat.localDate(previous.firstDay)) a \(ReportFormat.localDate(previous.lastDay))")
    }
}
