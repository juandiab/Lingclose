import SwiftUI

/// Apariencia elegida en Ajustes. `system` sigue el modo de iOS.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: Self { self }

    /// Esquema para `.preferredColorScheme`; `nil` deja que decida el sistema.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: String(localized: "settings.appearance.system", defaultValue: "Sistema")
        case .light: String(localized: "settings.appearance.light", defaultValue: "Claro")
        case .dark: String(localized: "settings.appearance.dark", defaultValue: "Oscuro")
        }
    }

    /// Interpreta un valor guardado; cualquier cosa desconocida cuenta como `system`.
    init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .system
    }
}
