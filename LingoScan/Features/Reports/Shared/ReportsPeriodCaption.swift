import LingoCore
import SwiftUI

/// Bajo el selector: fechas del período y días con datos; un indicador mientras se calcula.
struct ReportsPeriodCaption: View {
    let content: ReportContent?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            if let content {
                Text(caption(content))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "reports.loading", defaultValue: "Calculando reportes"))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
    }

    private func caption(_ content: ReportContent) -> String {
        let summary = content.bundle.summary
        let range = ReportFormat.range(content.bundle.period)
        return String(
            localized: "reports.period.caption",
            defaultValue: "\(range) · \(summary.daysWithData) de \(content.bundle.dayCount) días con datos"
        )
    }
}
