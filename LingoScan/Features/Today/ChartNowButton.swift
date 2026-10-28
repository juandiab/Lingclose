import SwiftUI

/// Botón de vidrio "Ahora" sobre la esquina superior derecha de la curva: aparece cuando la ventana visible
/// dejó de estar en vivo y la devuelve al presente (con animación salvo Reduce Motion).
struct ChartNowButton: View {
    let viewModel: TodayViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !viewModel.isLive {
            Button(action: goToNow) {
                Label(String(localized: "today.chart.now", defaultValue: "Ahora"), systemImage: "arrow.right.to.line")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Tokens.Spacing.sm)
                    .frame(minHeight: 44)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityHint(String(localized: "today.chart.now.hint", defaultValue: "Vuelve la curva al momento actual"))
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }

    private func goToNow() {
        withAnimation(reduceMotion ? nil : .snappy) { viewModel.goToNow() }
    }
}
