import SwiftUI

/// Botón "i" junto a la lectura de la curva: abre la leyenda (`ChartLegend`) en un popover.
struct ChartLegendButton: View {
    let low: Int
    let high: Int
    @State private var isShowing = false

    var body: some View {
        Button(
            String(localized: "today.legend.button", defaultValue: "Leyenda de la curva"),
            systemImage: "info.circle",
            action: show
        )
        .labelStyle(.iconOnly)
        .foregroundStyle(.secondary)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .popover(isPresented: $isShowing) {
            ChartLegend(low: low, high: high)
                .padding(Tokens.Spacing.sm)
                .frame(idealWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func show() {
        isShowing = true
    }
}

#Preview {
    ChartLegendButton(low: 70, high: 140)
}
