import SwiftUI

/// Esquema de color de la app: siempre la apariencia de Ajustes (Sistema / Claro / Oscuro), con o sin fondo animado.
/// Hex Vault tiene variante clara y oscura (T-30, D-33); el fondo ya no fuerza el modo oscuro.
///
/// Va en la raíz (`LingoScanApp`), en lugar de `.preferredColorScheme(appearance.colorScheme)`: un
/// `preferredColorScheme` exterior (aunque sea `nil`) anula al de las pantallas, así que la decisión se toma
/// en un único sitio.
struct AppColorSchemeModifier: ViewModifier {
    @AppStorage(BackgroundStyle.storageKey) private var styleRaw = BackgroundStyle.default.rawValue
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system

    func body(content: Content) -> some View {
        content.preferredColorScheme(
            Self.colorScheme(style: BackgroundStyle(stored: styleRaw), appearance: appearance))
    }

    /// La apariencia manda siempre; `style` se mantiene en la firma para que la decisión siga en un único sitio.
    static func colorScheme(style: BackgroundStyle, appearance: AppearanceMode) -> ColorScheme? {
        appearance.colorScheme
    }
}

extension View {
    /// Aplica el esquema de color de la app (ver `AppColorSchemeModifier`).
    func appColorScheme() -> some View {
        modifier(AppColorSchemeModifier())
    }
}
