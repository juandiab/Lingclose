import LingoCore
import SwiftUI

/// Tarjeta discreta "Qué hacer" bajo la cabecera de Hoy (T-25): aparece tras tocar una notificación con consejo,
/// muestra hasta 2 consejos de reglas y, si hay asistente configurado, "Preguntar al asistente". Se cierra con la
/// X y no vuelve hasta la siguiente alerta.
struct CoachingCard: View {
    let record: CoachingRecord
    let canAskAssistant: Bool
    let onAsk: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                        Text(String(localized: "coaching.card.title", defaultValue: "Qué hacer"))
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Tokens.Spacing.xs)
                    Button(String(localized: "coaching.card.dismiss", defaultValue: "Cerrar"), systemImage: "xmark", action: onDismiss)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                ForEach(record.tips) { tip in
                    CoachingTipRow(tip: tip)
                }
                if canAskAssistant {
                    Button(String(localized: "coaching.card.ask", defaultValue: "Preguntar al asistente"), systemImage: "sparkles", action: onAsk)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Text(String(localized: "coaching.card.disclaimer", defaultValue: "Informativo, no es consejo médico."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Tras la alerta Alta · 165 mg/dL".
    private var subtitle: String {
        let kind = record.context.kind.settingsTitle
        if let value = record.context.value {
            return String(localized: "coaching.card.subtitle", defaultValue: "Tras la alerta \(kind) · \(value) mg/dL")
        }
        return String(localized: "coaching.card.subtitle.noValue", defaultValue: "Tras la alerta \(kind)")
    }
}

#Preview {
    let context = CoachingContext(kind: .high, value: 165, minutesSinceLastMeal: 40, hour: 14)
    CoachingCard(
        record: CoachingRecord(id: "p", context: context, tipIDs: CoachingRules.tips(for: context).map(\.id),
                               createdAt: .now, openedAt: .now),
        canAskAssistant: true, onAsk: {}, onDismiss: {})
    .padding()
}
