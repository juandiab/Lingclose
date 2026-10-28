import SwiftUI

/// Una métrica de la fila de estadísticas: etiqueta pequeña, valor `.rounded` y unidad opcional.
struct PeriodStatMetric: View {
    let title: String
    /// Valor ya formateado; `nil` se muestra como "--".
    let value: String?
    var unit: String?
    /// Lectura de VoiceOver; sin ella se anuncia "<título>, sin datos".
    let spoken: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xxs) {
                Text(verbatim: value ?? "--")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                if let unit, value != nil {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? String(localized: "today.stats.none.a11y", defaultValue: "\(title), sin datos"))
    }
}
