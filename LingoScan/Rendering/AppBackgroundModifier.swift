import SwiftUI

/// Fondo de una raíz de pestaña: Hex Vault o, con "Ninguno", el fondo del sistema.
/// La variante (clara u oscura) sigue la apariencia de Ajustes; la pone `AppColorSchemeModifier` en la raíz.
///
/// Va dentro del `NavigationStack` (usa `containerBackground(for: .navigation)`): el contenedor del `TabView`
/// de iOS 26 es opaco y una capa detrás de él no se vería.
struct AppBackgroundModifier: ViewModifier {
    @AppStorage(BackgroundStyle.storageKey) private var styleRaw = BackgroundStyle.default.rawValue

    func body(content: Content) -> some View {
        let animated = BackgroundStyle(stored: styleRaw).isAnimated
        content
            .scrollContentBackground(animated ? .hidden : .automatic)
            .containerBackground(for: .navigation) {
                if animated {
                    BackgroundSlot().ignoresSafeArea()
                }
            }
    }
}

extension View {
    /// Pone el fondo animado compartido como fondo del contenedor de navegación de esta pantalla.
    func appBackground() -> some View {
        modifier(AppBackgroundModifier())
    }
}
