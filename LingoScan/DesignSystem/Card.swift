import SwiftUI

/// Superficie sólida para texto y gráficas: fondo → tarjeta → contenido.
/// Nunca lleva vidrio: la gráfica y las tablas van sobre `secondarySystemBackground`.
struct Card<Content: View>: View {
    var isElevated = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(Tokens.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: Tokens.Radius.card))
            .shadow(color: .black.opacity(isElevated ? 0.08 : 0), radius: 2, y: 1)
    }
}

#Preview {
    Card(isElevated: true) {
        Text("Tarjeta")
    }
    .padding()
}
