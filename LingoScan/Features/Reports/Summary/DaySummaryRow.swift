import LingoCore
import SwiftUI

/// Un día del resumen: fecha, barra de bandas, en rango, media y cobertura.
struct DaySummaryRow: View {
    let summary: DaySummary

    var body: some View {
        let stats = summary.stats
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(ReportFormat.day(summary.day))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: Tokens.Spacing.xs)
                if stats.hasReadings {
                    Text(String(
                        localized: "reports.day.values",
                        defaultValue: "\(ReportFormat.percent(stats.timeInRange) ?? "--") en rango · media \(ReportFormat.mgdl(stats.mean) ?? "--")"
                    ))
                    .font(.footnote)
                    .monospacedDigit()
                }
            }
            if stats.hasReadings {
                ReportBandBar(stats: stats, height: 8)
            }
            Text(note)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var note: String {
        let coverage = ReportFormat.percent(summary.stats.coverage) ?? "0 %"
        if !summary.stats.hasReadings {
            return String(localized: "reports.day.noData", defaultValue: "Sin lecturas")
        }
        if summary.hasEnoughData {
            return String(localized: "reports.day.coverage", defaultValue: "Datos el \(coverage) del día")
        }
        return String(localized: "reports.day.lowCoverage", defaultValue: "Datos el \(coverage) del día: poco para compararlo con otros")
    }
}
