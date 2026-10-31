import SwiftUI

/// Ajustes › Personalización › Fondo: Hex Vault (por defecto) o Ninguno. Selector visual con miniaturas (la miniatura es
/// lo que explica cada opción); el cambio se aplica en vivo y sigue la apariencia elegida, en claro o en oscuro.
struct BackgroundStyleRow: View {
    @AppStorage(BackgroundStyle.storageKey) private var styleRaw = BackgroundStyle.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        let style = BackgroundStyle(stored: styleRaw)
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Label(String(localized: "settings.background", defaultValue: "Fondo"), systemImage: "square.stack.3d.down.right")
            HStack(spacing: Tokens.Spacing.sm) {
                ForEach(BackgroundStyle.allCases) { option in
                    BackgroundStyleOption(
                        style: option,
                        isSelected: option == style,
                        namespace: selectionNamespace
                    ) { select(option) }
                }
            }
            .sensoryFeedback(.selection, trigger: styleRaw)
            Text(String(
                localized: "settings.background.footer",
                defaultValue: "Hex Vault es un fondo animado que toma el color de tu última lectura: verde en rango, ámbar por encima, azul por debajo y gris sin dato reciente."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, Tokens.Spacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "settings.background", defaultValue: "Fondo"))
    }

    private func select(_ option: BackgroundStyle) {
        withAnimation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion)) {
            styleRaw = option.rawValue
        }
    }
}

#Preview {
    Form {
        BackgroundStyleRow()
    }
}
