import LingoCore
import SwiftUI

/// Card de resumen: tiempo por banda (barra apilada y leyenda) y estadísticas del período.
struct SummaryCardContent: View {
    let report: PeriodSummaryReport
    let configuration: ReportConfiguration

    var body: some View {
        if report.hasEnoughData {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportBandBar(stats: report.stats)
                ReportBandLegend(stats: report.stats, configuration: configuration)
                Divider()
                SummaryTiles(report: report)
            }
        } else {
            ReportEmptyState(message: String(
                localized: "reports.summary.empty",
                defaultValue: "Aún no hay lecturas en este período. El resumen aparece con el primer día de datos."))
        }
    }
}
