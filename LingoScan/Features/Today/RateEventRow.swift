import LingoCore
import SwiftUI

/// Una subida o bajada rápida: dirección, horas, de→a y pendiente.
struct RateEventRow: View {
    let event: RateEvent

    var body: some View {
        let rising = event.direction == .rising
        HStack(spacing: Tokens.Spacing.xs) {
            Image(systemName: rising ? "arrow.up.right" : "arrow.down.right")
                .foregroundStyle(rising ? Tokens.Palette.high : Tokens.Palette.low)
                .accessibilityLabel(rising
                    ? String(localized: "today.insights.rate.up.a11y", defaultValue: "Subida rápida")
                    : String(localized: "today.insights.rate.down.a11y", defaultValue: "Bajada rápida"))
            VStack(alignment: .leading, spacing: 0) {
                Text(event.start.date..<event.end.date, format: .interval.hour().minute())
                    .font(.subheadline)
                Text(InsightFormat.rateRange(event))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Spacing.xs)
            Text(InsightFormat.rateSlope(event))
                .font(.subheadline.weight(.semibold))
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}
