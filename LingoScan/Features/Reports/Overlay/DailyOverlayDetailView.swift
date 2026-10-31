import LingoCore
import SwiftUI

/// Detalle de días superpuestos: gráfica a 5 min (hasta 14 días) y la lista de días con sus cifras.
struct DailyOverlayDetailView: View {
    let content: ReportContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportCard(
                    title: String(localized: "reports.overlay.title", defaultValue: "Días superpuestos"),
                    systemImage: "square.stack.3d.down.right",
                    caption: ReportFormat.range(content.bundle.period)
                ) {
                    DailyOverlayCardContent(content: content, detailed: true, chartHeight: 300)
                    Text(String(
                        localized: "reports.overlay.explainer",
                        defaultValue: "Cada línea es un día, todos sobre el mismo reloj. Las líneas que se agrupan señalan horas parecidas de un día a otro; las que se separan, horas que cambian."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ReportCard(
                    title: String(localized: "reports.summary.days", defaultValue: "Por día"),
                    systemImage: "calendar"
                ) {
                    LazyVStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                        ForEach(content.bundle.dailyOverlay.days.filter(\.summary.stats.hasReadings).reversed(), id: \.summary.day.date) { day in
                            DaySummaryRow(summary: day.summary)
                        }
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }
}
