import SwiftUI

/// Chip de vidrio para chrome flotante (selector de período, estado del sensor).
///
/// Varios chips juntos van dentro de un `GlassEffectContainer` que pone quien los agrupa.
/// `.glassEffect` se aplica después del padding y el tamaño mínimo (44 pt).
struct GlassChip: View {
    let title: String
    var systemImage: String?
    /// Color del icono; el texto conserva el color primario para mantener la legibilidad.
    var iconTint: Color?
    /// Pulso del icono mientras reconecta; quien lo usa lo apaga con Reduce Motion.
    var isPulsing = false
    var isSelected = false
    var isInteractive = true

    var body: some View {
        Group {
            if let systemImage {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(iconTint ?? .primary)
                        .symbolEffect(.pulse, isActive: isPulsing)
                }
            } else {
                Text(title)
            }
        }
        .font(.subheadline)
        .bold(isSelected)
        .padding(.horizontal, Tokens.Spacing.sm)
        .frame(minHeight: 44)
        .glassEffect(glass, in: .capsule)
    }

    private var glass: Glass {
        let base: Glass = isSelected ? .regular.tint(.accentColor.opacity(0.35)) : .regular
        return base.interactive(isInteractive)
    }
}

#Preview {
    GlassEffectContainer(spacing: Tokens.Spacing.xs) {
        HStack(spacing: Tokens.Spacing.xs) {
            GlassChip(title: "3 h")
            GlassChip(title: "6 h", isSelected: true)
            GlassChip(title: "24 h", systemImage: "clock")
        }
    }
    .padding()
}
