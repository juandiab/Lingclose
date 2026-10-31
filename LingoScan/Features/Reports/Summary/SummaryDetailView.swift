import LingoCore
import SwiftUI

/// Detalle del resumen: bandas, estadísticas completas (mínimo y máximo incluidos) y cada día del período.
struct SummaryDetailView: View {
    let content: ReportContent

    var body: some View {
        let report = content.bundle.summary
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportCard(
                    title: String(localized: "reports.summary.title", defaultValue: "Resumen del período"),
                    systemImage: "square.grid.2x2",
                    caption: ReportFormat.range(content.bundle.period)
                ) {
                    SummaryCardContent(report: report, configuration: content.configuration)
                    if report.hasEnoughData {
                        ReportStatGrid {
                            ReportStatTile(
                                title: String(localized: "reports.stat.min", defaultValue: "Mínimo"),
                                value: report.stats.minimum.map { "\($0)" }, unit: "mg/dL")
                            ReportStatTile(
                                title: String(localized: "reports.stat.max", defaultValue: "Máximo"),
                                value: report.stats.maximum.map { "\($0)" }, unit: "mg/dL")
                            ReportStatTile(
                                title: String(localized: "reports.stat.longestGap", defaultValue: "Hueco más largo"),
                                value: report.gaps > 0 ? ReportFormat.duration(minutes: report.longestGapMinutes) : nil)
                        }
                    }
                }
                ReportCard(
                    title: String(localized: "reports.summary.days", defaultValue: "Por día"),
                    systemImage: "calendar",
                    caption: String(
                        localized: "reports.summary.days.caption",
                        defaultValue: "Un día cuenta para comparar si tiene datos al menos el \(ReportFormat.percent(ReportThresholds.minimumDayCoverage) ?? "50 %") del tiempo.")
                ) {
                    let days = report.days.filter(\.stats.hasReadings).reversed()
                    LazyVStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                        ForEach(days, id: \.day.date) { day in
                            DaySummaryRow(summary: day)
                            if day.day.date != days.last?.day.date { Divider() }
                        }
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }
}
