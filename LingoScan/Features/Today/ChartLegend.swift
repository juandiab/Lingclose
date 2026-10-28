import SwiftUI

/// Leyenda de la curva: líneas de referencia (no médicas), índice de pico y huecos.
struct ChartLegend: View {
    let low: Int
    let high: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack(spacing: Tokens.Spacing.xs) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Tokens.Palette.high.opacity(0.3))
                    .frame(width: 20, height: 12)
                    .accessibilityHidden(true)
                Text(String(
                    localized: "today.legend.spike",
                    defaultValue: "Rojo sobre \(high) mg/dL; el número bajo cada pico es el índice de pico. Líneas de referencia \(low) y \(high) mg/dL · no médico"
                ))
            }
            HStack(spacing: Tokens.Spacing.xs) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Tokens.Palette.low.opacity(0.3))
                    .frame(width: 20, height: 12)
                    .accessibilityHidden(true)
                Text(String(
                    localized: "today.legend.low",
                    defaultValue: "Azul bajo \(low) mg/dL"
                ))
            }
            HStack(spacing: Tokens.Spacing.xs) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Tokens.Palette.gap.opacity(0.35))
                    .frame(width: 20, height: 12)
                    .accessibilityHidden(true)
                Text(String(
                    localized: "today.legend.gap",
                    defaultValue: "Hueco: más de 15 min sin lecturas válidas, no se interpola"
                ))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
