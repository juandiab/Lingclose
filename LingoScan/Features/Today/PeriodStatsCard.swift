import LingoCore
import SwiftUI

/// Tiempo en rango (70–180), media y SD del período visible, sobre superficie sólida y con la nota "no médico".
struct PeriodStatsCard: View {
    let stats: BasicStats
    let period: TodayPeriod

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                Text(String(localized: "today.stats.title", defaultValue: "Período visible (\(period.title))"))
                    .font(.headline)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Tokens.Spacing.md) { metrics }
                    VStack(alignment: .leading, spacing: Tokens.Spacing.sm) { metrics }
                }
                if let coverage = stats.coverage {
                    Text(String(localized: "today.stats.coverage", defaultValue: "Con datos el \(coverage.formatted(.percent.precision(.fractionLength(0)))) del período."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(String(localized: "today.stats.note", defaultValue: "Informativo; no es un dispositivo médico. Rango de referencia \(stats.range.lowerBound)–\(stats.range.upperBound) mg/dL."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var metrics: some View {
        metric(
            title: String(localized: "today.stats.tir", defaultValue: "En rango"),
            value: stats.timeInRange.map { $0.formatted(.percent.precision(.fractionLength(0))) },
            spoken: stats.timeInRange.map { String(localized: "today.stats.tir.a11y", defaultValue: "En rango, \($0.formatted(.percent.precision(.fractionLength(0))))") })
        metric(
            title: String(localized: "today.stats.mean", defaultValue: "Media"),
            value: stats.mean.map { "\(Int($0.rounded())) mg/dL" },
            spoken: stats.mean.map { String(localized: "today.stats.mean.a11y", defaultValue: "Media, \(Int($0.rounded())) miligramos por decilitro") })
        metric(
            title: String(localized: "today.stats.sd", defaultValue: "SD"),
            value: stats.standardDeviation.map { "\(Int($0.rounded())) mg/dL" },
            spoken: stats.standardDeviation.map { String(localized: "today.stats.sd.a11y", defaultValue: "Desviación estándar, \(Int($0.rounded())) miligramos por decilitro") })
    }

    private func metric(title: String, value: String?, spoken: String?) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(verbatim: value ?? "--")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? String(localized: "today.stats.none.a11y", defaultValue: "\(title), sin datos"))
    }
}
