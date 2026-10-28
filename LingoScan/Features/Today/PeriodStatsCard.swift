import LingoCore
import SwiftUI

/// Tiempo en rango, media y SD del período visible en una fila compacta, sin tarjeta. La nota "no médico"
/// vive en el pie de Hoy.
struct PeriodStatsCard: View {
    let stats: BasicStats
    /// Longitud visible ya formateada ("4 h 30 min").
    let lengthTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            let tir = PeriodStatMetric(
                title: String(localized: "today.stats.tir", defaultValue: "En rango"),
                value: stats.timeInRange.map { $0.formatted(.percent.precision(.fractionLength(0))) },
                spoken: stats.timeInRange.map { String(localized: "today.stats.tir.a11y", defaultValue: "En rango, \($0.formatted(.percent.precision(.fractionLength(0))))") })
            let mean = PeriodStatMetric(
                title: String(localized: "today.stats.mean", defaultValue: "Media"),
                value: stats.mean.map { "\(Int($0.rounded()))" },
                unit: "mg/dL",
                spoken: stats.mean.map { String(localized: "today.stats.mean.a11y", defaultValue: "Media, \(Int($0.rounded())) miligramos por decilitro") })
            let sd = PeriodStatMetric(
                title: String(localized: "today.stats.sd", defaultValue: "SD"),
                value: stats.standardDeviation.map { "\(Int($0.rounded()))" },
                unit: "mg/dL",
                spoken: stats.standardDeviation.map { String(localized: "today.stats.sd.a11y", defaultValue: "Desviación estándar, \(Int($0.rounded())) miligramos por decilitro") })
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Tokens.Spacing.sm) { tir; mean; sd }
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) { tir; mean; sd }
            }
        }
        .padding(.vertical, Tokens.Spacing.xxs)
        .accessibilityElement(children: .contain)
    }

    /// "Período visible (6 h) · datos el 98 %".
    private var caption: String {
        let title = String(localized: "today.stats.title", defaultValue: "Período visible (\(lengthTitle))")
        guard let coverage = stats.coverage else { return title }
        let percent = coverage.formatted(.percent.precision(.fractionLength(0)))
        return title + " · " + String(localized: "today.stats.coverage.short", defaultValue: "datos el \(percent)")
    }
}
