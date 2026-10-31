import LingoCore
import SwiftUI

/// Detalle de noches: resumen y todas las noches del período.
struct NightsDetailView: View {
    let content: ReportContent

    var body: some View {
        let report = content.bundle.nights
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportCard(
                    title: String(localized: "reports.nights.title", defaultValue: "Noche"),
                    systemImage: "moon.stars",
                    caption: String(
                        localized: "reports.nights.caption",
                        defaultValue: "Noches \(ReportNames.nightWindow(content.configuration)). Bajada: al menos 15 min por debajo de \(content.configuration.rangeLow) mg/dL.")
                ) {
                    NightsCardContent(report: report, configuration: content.configuration, recentCount: 0)
                }
                ForEach(Array(report.nights.filter(\.stats.hasReadings).reversed()), id: \.night) { night in
                    NightRow(night: night, configuration: content.configuration)
                        .padding(Tokens.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .reportSurface()
                }
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }
}
