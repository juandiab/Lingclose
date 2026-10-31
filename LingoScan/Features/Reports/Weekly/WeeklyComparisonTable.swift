import LingoCore
import SwiftUI

/// Tabla: métrica, esta semana, la anterior y el cambio.
struct WeeklyComparisonTable: View {
    let report: WeeklyComparisonReport
    let metrics: [WeeklyMetric]
    let configuration: ReportConfiguration

    var body: some View {
        if let current = report.current, let previous = report.previous, let deltas = report.deltas {
            Grid(alignment: .leading, horizontalSpacing: Tokens.Spacing.sm, verticalSpacing: Tokens.Spacing.xs) {
                GridRow {
                    Text(verbatim: "")
                    Text(String(localized: "reports.weekly.current", defaultValue: "Esta semana"))
                    Text(String(localized: "reports.weekly.previous", defaultValue: "Anterior"))
                    Text(String(localized: "reports.weekly.change", defaultValue: "Cambio"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(metrics) { metric in
                    let delta = metric.delta(current: current, previous: previous, deltas: deltas, configuration: configuration)
                    GridRow {
                        Text(metric.title)
                            .font(.subheadline)
                        Text(verbatim: metric.value(current))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(verbatim: metric.value(previous))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let delta {
                            ReportDeltaLabel(delta: delta)
                        } else {
                            Text(verbatim: "--")
                        }
                    }
                    .monospacedDigit()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(metric, current: current, previous: previous, delta: delta))
                }
            }
        }
    }

    private func spoken(
        _ metric: WeeklyMetric,
        current: WeeklyComparisonReport.Week,
        previous: WeeklyComparisonReport.Week,
        delta: ReportDelta?
    ) -> String {
        let base = String(
            localized: "reports.weekly.row.a11y",
            defaultValue: "\(metric.title): esta semana \(metric.value(current)), la anterior \(metric.value(previous))")
        guard let delta else { return base }
        return "\(base), \(delta.text), \(delta.spokenJudgment)"
    }
}
