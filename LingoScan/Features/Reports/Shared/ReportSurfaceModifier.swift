import SwiftUI

/// Superficie de las cards de Reportes: card sólida Studio con Hex Vault (claro u oscuro) o en oscuro del sistema, y
/// la tarjeta del sistema en claro con fondo "Ninguno", para que el texto primario siempre tenga contraste.
/// Sobre la base clara de Hex Vault (≈ 0,97) la tarjeta gris del sistema casi no se distingue; la card Studio clara
/// es blanca con borde y sombra suave (T-30).
struct ReportSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(BackgroundStyle.storageKey) private var styleRaw = BackgroundStyle.default.rawValue

    func body(content: Content) -> some View {
        if colorScheme == .dark || BackgroundStyle(stored: styleRaw).isAnimated {
            content.studioCard()
        } else {
            content.background(Color(.secondarySystemBackground), in: .rect(cornerRadius: Tokens.Radius.card))
        }
    }
}

extension View {
    func reportSurface() -> some View {
        modifier(ReportSurfaceModifier())
    }
}
