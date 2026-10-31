import SwiftUI

/// Ajustes › Fondo: Hex Vault (por defecto) o Ninguno, con miniaturas. El cambio se aplica en vivo:
/// el host del fondo funde al nuevo renderer sin recrear la vista.
struct BackgroundStyleSection: View {
    @AppStorage(BackgroundStyle.storageKey) private var styleRaw = BackgroundStyle.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        let style = BackgroundStyle(stored: styleRaw)
        Section {
            HStack(spacing: Tokens.Spacing.sm) {
                ForEach(BackgroundStyle.allCases) { option in
                    BackgroundStyleOption(
                        style: option,
                        isSelected: option == style,
                        namespace: selectionNamespace
                    ) { select(option) }
                }
            }
            .padding(.vertical, Tokens.Spacing.xxs)
            .sensoryFeedback(.selection, trigger: styleRaw)
        } header: {
            Text(String(localized: "settings.background", defaultValue: "Fondo"))
        } footer: {
            Text(String(
                localized: "settings.background.footer",
                defaultValue: "Hex Vault es un fondo animado que toma el color de tu última lectura: verde en rango, ámbar por encima, azul por debajo y gris sin dato reciente. El fondo sigue la apariencia elegida arriba, en claro o en oscuro."
            ))
        }
    }

    private func select(_ option: BackgroundStyle) {
        withAnimation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion)) {
            styleRaw = option.rawValue
        }
    }
}

#Preview {
    Form {
        BackgroundStyleSection()
    }
}
