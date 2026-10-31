import LingoCore
import SwiftUI

/// Leyenda de la barra de bandas: color, nombre, límites en mg/dL y porcentaje de cada banda.
struct ReportBandLegend: View {
    let stats: GlucoseStats
    let configuration: ReportConfiguration

    var body: some View {
        let shares = ReportBandShare.shares(stats)
        ReportStatGrid {
            ForEach(shares) { share in
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xs) {
                    Circle()
                        .fill(ReportPalette.color(for: share.band))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: ReportFormat.percent(share.fraction) ?? "--")
                            .font(.system(.headline, design: .rounded))
                            .monospacedDigit()
                        Text(ReportNames.band(share.band))
                            .font(.caption)
                        Text(verbatim: ReportNames.bandLimits(share.band, configuration: configuration))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(
                    localized: "reports.band.a11y",
                    defaultValue: "\(ReportNames.band(share.band)), \(ReportFormat.percent(share.fraction) ?? "--") del tiempo, \(ReportNames.bandLimits(share.band, configuration: configuration)) miligramos por decilitro"
                ))
            }
        }
    }
}
