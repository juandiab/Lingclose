import LingoCore
import SwiftUI

/// Fila de un evento: icono, tipo con su detalle, texto y hora. Un solo elemento para VoiceOver.
struct DiaryRow: View {
    let event: DiaryEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
            Image(systemName: event.kind.systemImage)
                .foregroundStyle(.tint)
                .frame(minWidth: Tokens.Spacing.md)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                HStack(spacing: Tokens.Spacing.xs) {
                    Text(event.kind.title)
                        .font(.headline)
                    if event.synthetic {
                        Text(String(localized: "diary.synthetic", defaultValue: "Ejemplo"))
                            .font(.caption)
                            .padding(.horizontal, Tokens.Spacing.xs)
                            .background(.quaternary, in: .capsule)
                    }
                }
                if let detail = event.detailText {
                    Text(detail)
                        .font(.subheadline)
                        .monospacedDigit()
                }
                if let text = event.text {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Tokens.Spacing.xs)
            Text(event.at.date, format: .dateTime.hour().minute())
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(event.spokenSummary + (event.synthetic ? ", " + String(localized: "diary.synthetic.a11y", defaultValue: "dato de ejemplo") : ""))
    }
}
