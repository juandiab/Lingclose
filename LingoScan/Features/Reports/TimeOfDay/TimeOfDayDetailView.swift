import LingoCore
import SwiftUI

/// Detalle de patrones por franja: cada franja con todas sus cifras.
struct TimeOfDayDetailView: View {
    let content: ReportContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportCard(
                    title: String(localized: "reports.slots.title", defaultValue: "Patrones por franja"),
                    systemImage: "sun.horizon",
                    caption: String(
                        localized: "reports.slots.explainer",
                        defaultValue: "Subida o bajada rápida: más de \(Int(content.configuration.fastChangeThreshold)) mg/dL por minuto durante un rato.")
                ) {
                    TimeOfDayCardContent(
                        report: content.bundle.timeOfDay,
                        daysWithData: content.bundle.summary.daysWithData,
                        showsDetail: true)
                }
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }
}
