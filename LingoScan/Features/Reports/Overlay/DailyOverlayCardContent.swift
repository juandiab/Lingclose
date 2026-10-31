import LingoCore
import SwiftUI

/// Card de días superpuestos: la gráfica y su leyenda, o qué falta para verla.
struct DailyOverlayCardContent: View {
    let content: ReportContent
    var detailed = false
    var chartHeight: CGFloat = 180

    var body: some View {
        let report = content.bundle.dailyOverlay
        if report.hasEnoughData {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                DailyOverlayChart(
                    points: detailed ? content.overlayDetailed : content.overlayCompact,
                    configuration: content.configuration,
                    dayCount: report.days.count)
                    .frame(height: chartHeight)
                HStack(spacing: Tokens.Spacing.sm) {
                    Label {
                        Text(String(localized: "reports.overlay.legend.latest", defaultValue: "Hoy"))
                    } icon: {
                        Capsule().fill(Color.primary).frame(width: 16, height: 3)
                    }
                    Label {
                        Text(String(localized: "reports.overlay.legend.others", defaultValue: "Otros días"))
                    } icon: {
                        Capsule().fill(Color.secondary.opacity(0.5)).frame(width: 16, height: 2)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        } else {
            ReportEmptyState(message: String(
                localized: "reports.overlay.empty",
                defaultValue: "Necesita al menos un día con datos el \(ReportFormat.percent(ReportThresholds.minimumDayCoverage) ?? "50 %") del tiempo o más."))
        }
    }
}
