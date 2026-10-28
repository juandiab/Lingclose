import SwiftUI

/// Valor válido más reciente, tendencia, antigüedad y estado, en un solo elemento para VoiceOver.
/// Bloque compacto: valor grande y, debajo, "tendencia · hace N min" y el estado de rango en dos líneas cortas.
struct CurrentValueView: View {
    let viewModel: TodayViewModel
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            MetricText(value: viewModel.latestValue, unit: "mg/dL")
            if let value = viewModel.latestValue, let minutes = viewModel.ageMinutes(at: now) {
                HStack(spacing: Tokens.Spacing.xs) {
                    trendLabel
                    Text(verbatim: "·")
                        .foregroundStyle(.secondary)
                    AgeText(minutes: minutes)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                RangeStatusLabel(value: value, isStale: viewModel.isStale(at: now), low: viewModel.referenceLow, high: viewModel.referenceHigh)
                    .font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.spokenSummary(at: now))
    }

    @ViewBuilder
    private var trendLabel: some View {
        if let trend = viewModel.trend {
            Label(trend.title, systemImage: trend.systemImage)
        } else {
            Text(TrendDirection.unknownTitle)
                .foregroundStyle(.secondary)
        }
    }
}
