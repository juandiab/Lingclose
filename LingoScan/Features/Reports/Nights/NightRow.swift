import LingoCore
import SwiftUI

/// Una noche: fecha, mediana, mínimo (con su hora), bajadas y cobertura.
struct NightRow: View {
    let night: NightReport.Night
    let configuration: ReportConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "reports.night.date", defaultValue: "Noche del \(ReportFormat.localDate(night.night))"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: Tokens.Spacing.xs)
                if night.lowEpisodes > 0 {
                    Label(
                        String(localized: "reports.night.lows", defaultValue: "\(night.lowEpisodes) bajadas"),
                        systemImage: "arrow.down.to.line")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ReportPalette.low)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
                fact(String(localized: "reports.night.median", defaultValue: "Mediana"), ReportFormat.mgdl(night.median))
                fact(String(localized: "reports.stat.min", defaultValue: "Mínimo"), night.stats.minimum.map { "\($0)" }, color: minimumColor)
                fact(String(localized: "reports.stat.tir", defaultValue: "En rango"), ReportFormat.percent(night.stats.timeInRange))
            }
            Text(coverageNote)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var minimumColor: Color? {
        guard let minimum = night.stats.minimum, minimum < configuration.rangeLow else { return nil }
        return ReportPalette.low
    }

    private var coverageNote: String {
        var parts: [String] = []
        if let time = night.minimumAt {
            parts.append(String(localized: "reports.night.minimumAt", defaultValue: "mínimo a las \(time.date.formatted(date: .omitted, time: .shortened))"))
        }
        let coverage = ReportFormat.percent(night.stats.coverage) ?? "0 %"
        parts.append(night.isReliable
            ? String(localized: "reports.night.coverage", defaultValue: "datos el \(coverage)")
            : String(localized: "reports.night.lowCoverage", defaultValue: "datos solo el \(coverage): no cuenta para el resumen"))
        return parts.joined(separator: " · ")
    }

    private func fact(_ title: String, _ value: String?, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: value ?? "--")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color ?? .primary)
        }
    }
}
