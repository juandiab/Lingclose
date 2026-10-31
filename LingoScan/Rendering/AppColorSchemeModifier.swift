import SwiftUI

/// Esquema de color de la app: con fondo animado, estudio oscuro; con "Ninguno", la apariencia de Ajustes
/// (Sistema / Claro / Oscuro).
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

    static func colorScheme(style: BackgroundStyle, appearance: AppearanceMode) -> ColorScheme? {
        style.isAnimated ? .dark : appearance.colorScheme
    }
}

extension View {
    /// Aplica el esquema de color de la app (ver `AppColorSchemeModifier`).
    func appColorScheme() -> some View {
        modifier(AppColorSchemeModifier())
    }
}
