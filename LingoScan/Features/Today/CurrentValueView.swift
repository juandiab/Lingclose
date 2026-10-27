import SwiftUI

/// Valor válido más reciente, tendencia, antigüedad y estado, en un solo elemento para VoiceOver.
struct CurrentValueView: View {
    let viewModel: TodayViewModel
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            MetricText(value: viewModel.latestValue, unit: "mg/dL")
            if let value = viewModel.latestValue, let minutes = viewModel.ageMinutes(at: now) {
                HStack(spacing: Tokens.Spacing.xs) {
                    trendLabel
                    Text(verbatim: "·")
                        .foregroundStyle(.secondary)
                    AgeText(minutes: minutes)
                        .monospacedDigit()
                }
                .font(.title3)
                RangeStatusLabel(value: value, isStale: viewModel.isStale(at: now))
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
