import LingoCore
import SwiftUI

/// Card del perfil por hora: la gráfica y su leyenda, o qué falta para verla.
struct HourlyProfileCardContent: View {
    let content: ReportContent
    var chartHeight: CGFloat = 200

    var body: some View {
        let report = content.bundle.hourlyProfile
        if report.hasEnoughData {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HourlyProfileChart(points: content.profile, configuration: content.configuration)
                    .frame(height: chartHeight)
                HourlyProfileLegend()
                if report.reportedBins < HourlyProfileReport.binCount {
                    Text(String(
                        localized: "reports.profile.partial",
                        defaultValue: "\(report.reportedBins) de \(HourlyProfileReport.binCount) medias horas con datos de al menos \(ReportThresholds.minimumDaysPerHourlyBin) días."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            ReportEmptyState(message: String(
                localized: "reports.profile.empty",
                defaultValue: "El perfil por hora necesita al menos \(ReportThresholds.minimumDaysPerHourlyBin) días con lecturas a la misma hora. Días con datos ahora: \(content.bundle.summary.daysWithData)."))
        }
    }
}
