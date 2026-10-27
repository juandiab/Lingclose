import LingoCore
import SwiftUI

/// "+" flotante de vidrio que se despliega en Comida / Ejercicio / Nota (morfología Liquid Glass: los tres
/// botones salen del propio "+"). Un toque fuera o en la "×" lo pliega. Respeta Reducir movimiento.
struct TodayAddMenu: View {
    let onChoose: (DiaryEventKind) -> Void

    @State private var isExpanded = false
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                // Captura el toque fuera del menú para plegarlo sin disparar nada debajo.
                Color.clear
                    .contentShape(.rect)
                    .ignoresSafeArea()
                    .onTapGesture { toggle() }
                    .accessibilityHidden(true)
            }
            GlassEffectContainer(spacing: Tokens.Spacing.xs) {
                VStack(alignment: .trailing, spacing: Tokens.Spacing.xs) {
                    if isExpanded {
                        ForEach(DiaryEventKind.creatable.reversed(), id: \.self) { kind in
                            option(kind)
                        }
                    }
                    plusButton
                }
            }
            .padding(Tokens.Spacing.sm)
        }
        .animation(animation, value: isExpanded)
    }

    private var plusButton: some View {
        Button {
            toggle()
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .rotationEffect(.degrees(isExpanded ? 45 : 0))
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("plus", in: glass)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded
            ? String(localized: "today.add.close", defaultValue: "Cerrar el menú de registro")
            : String(localized: "today.add", defaultValue: "Registrar comida, ejercicio o nota"))
        .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
    }

    private func option(_ kind: DiaryEventKind) -> some View {
        Button {
            isExpanded = false
            onChoose(kind)
        } label: {
            Label(kind.title, systemImage: kind.systemImage)
                .font(.body.weight(.semibold))
                .padding(.horizontal, Tokens.Spacing.sm)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID(kind.rawValue, in: glass)
        }
        .buttonStyle(.plain)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.4, anchor: .bottomTrailing).combined(with: .opacity),
            removal: .scale(scale: 0.4, anchor: .bottomTrailing).combined(with: .opacity)))
    }

    private var animation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.78)
    }

    private func toggle() {
        isExpanded.toggle()
    }
}

#Preview {
    ZStack(alignment: .bottomTrailing) {
        LinearGradient(colors: [.blue.opacity(0.3), .orange.opacity(0.3)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        TodayAddMenu { _ in }
    }
}
