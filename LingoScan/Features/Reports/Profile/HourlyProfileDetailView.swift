import LingoCore
import SwiftUI

/// Detalle del perfil por hora: gráfica grande, cómo leerla y la tabla cada 2 horas.
struct HourlyProfileDetailView: View {
    let content: ReportContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportCard(
                    title: String(localized: "reports.profile.title", defaultValue: "Perfil por hora del día"),
                    systemImage: "clock",
                    caption: ReportFormat.range(content.bundle.period)
                ) {
                    HourlyProfileCardContent(content: content, chartHeight: 300)
                    Text(String(
                        localized: "reports.profile.explainer",
                        defaultValue: "Todos los días del período apilados en uno. La línea es la mediana de cada media hora; la banda oscura reúne la mitad central de los valores y la clara, el 90 %. Una banda ancha indica días distintos entre sí a esa hora."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !content.profile.isEmpty {
                    ReportCard(
                        title: String(localized: "reports.profile.table", defaultValue: "Cada 2 horas"),
                        systemImage: "tablecells"
                    ) {
                        HourlyProfileTable(points: content.profile)
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }
}
