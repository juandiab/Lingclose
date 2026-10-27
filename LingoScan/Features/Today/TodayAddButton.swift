import SwiftUI

/// Botón "+" flotante de vidrio que abre el registro rápido.
struct TodayAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String(localized: "today.add", defaultValue: "Registrar comida, ejercicio o nota"), systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .padding(Tokens.Spacing.sm)
    }
}
