import SwiftUI

/// Leyenda de la curva: banda de referencia (no médica) y huecos.
struct ChartLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack(spacing: Tokens.Spacing.xs) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Tokens.Palette.inRange.opacity(0.25))
                    .frame(width: 20, height: 12)
                    .accessibilityHidden(true)
                Text(String(
                    localized: "today.legend.range",
                    defaultValue: "Rango de referencia 70–180 mg/dL · no médico"
                ))
            }
            HStack(spacing: Tokens.Spacing.xs) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Tokens.Palette.gap.opacity(0.35))
                    .frame(width: 20, height: 12)
                    .accessibilityHidden(true)
                Text(String(
                    localized: "today.legend.gap",
                    defaultValue: "Hueco: sin lecturas válidas, no se interpola"
                ))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
