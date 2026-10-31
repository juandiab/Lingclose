import LingoCore
import SwiftUI

/// Imagen para compartir: resumen del período en estudio oscuro, ancho fijo, con el aviso "no médico".
struct ReportSummaryShareView: View {
    let bundle: ReportBundle
    let isSynthetic: Bool

    static let width: CGFloat = 390

    var body: some View {
        let stats = bundle.summary.stats
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Text(verbatim: "Lingclose")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Tokens.Studio.textSecondary)
                Text(String(localized: "reports.share.title", defaultValue: "Resumen de \(bundle.dayCount) días"))
                    .font(.title2.weight(.bold))
                Text(String(
                    localized: "reports.share.subtitle",
                    defaultValue: "\(ReportFormat.range(bundle.period)) · \(bundle.summary.daysWithData) días con datos"
                ))
                .font(.subheadline)
                .foregroundStyle(Tokens.Studio.textSecondary)
            }
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportBandBar(stats: stats, height: 18)
                ReportBandLegend(stats: stats, configuration: bundle.configuration)
            }
            SummaryTiles(report: bundle.summary)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Text(String(
                    localized: "reports.share.note",
                    defaultValue: "Informativo, no es consejo médico · referencia \(bundle.configuration.rangeLow)–\(bundle.configuration.rangeHigh) mg/dL"
                ))
                if isSynthetic {
                    Text(String(localized: "reports.synthetic", defaultValue: "Datos de ejemplo (sintéticos). No son de un sensor real."))
                }
            }
            .font(.caption2)
            .foregroundStyle(Tokens.Studio.textTertiary)
        }
        .foregroundStyle(Tokens.Studio.textPrimary)
        .padding(Tokens.Spacing.md)
        .frame(width: Self.width, alignment: .leading)
        .background(Tokens.Studio.background)
        .environment(\.colorScheme, .dark)
    }
}
