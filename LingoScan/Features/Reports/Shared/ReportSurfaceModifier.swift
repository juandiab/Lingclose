import SwiftUI

/// Superficie de las cards de Reportes: card sólida Studio en oscuro (Hex Vault o sistema oscuro) y la tarjeta del
/// sistema en claro (fondo "Ninguno"), para que el texto primario siempre tenga contraste.
struct ReportSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
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
