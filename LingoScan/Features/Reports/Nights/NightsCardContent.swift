import LingoCore
import SwiftUI

/// Card de noches: resumen (≥ 3 noches con cobertura ≥ 70 %) y las últimas noches; si aún no hay resumen, qué falta
/// y las noches que ya hay.
struct NightsCardContent: View {
    let report: NightReport
    let configuration: ReportConfiguration
    var recentCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            if report.hasEnoughData {
                NightSummaryTiles(summary: report.summary)
            } else {
                ReportEmptyState(message: String(
                    localized: "reports.nights.empty",
                    defaultValue: "El resumen nocturno necesita \(ReportThresholds.minimumNightsForSummary) noches con datos al menos el \(ReportFormat.percent(ReportThresholds.minimumNightCoverage) ?? "70 %") del tiempo \(ReportNames.nightWindow(configuration)). Hay \(report.summary.reliableNights)."),
                    systemImage: "moon.zzz")
            }
            let recent = Array(report.nights.filter(\.stats.hasReadings).suffix(recentCount).reversed())
            if !recent.isEmpty {
                Divider()
                ForEach(recent, id: \.night) { night in
                    NightRow(night: night, configuration: configuration)
                }
            }
        }
    }
}
