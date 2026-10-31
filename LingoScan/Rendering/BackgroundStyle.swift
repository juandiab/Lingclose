import Foundation

/// Fondo animado elegido en Ajustes › Apariencia (persistido en `@AppStorage`).
///
/// v1: Hex Vault y "Ninguno". El contrato `BackgroundRenderer` deja sitio para añadir otros fondos.
enum BackgroundStyle: String, CaseIterable, Identifiable, Sendable {
    case hexVault
    case none

    static let storageKey = "background.style"
    static let `default`: BackgroundStyle = .hexVault

    var id: String { rawValue }

    /// Interpreta un valor guardado; cualquier cosa desconocida cuenta como el fondo por defecto.
    init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .default
    }

    /// Con fondo animado la app usa el estudio oscuro; con "Ninguno" sigue la apariencia elegida.
    var isAnimated: Bool { self != .none }

    var title: String {
        switch self {
        case .hexVault: String(localized: "settings.background.hexVault", defaultValue: "Hex Vault")
        case .none: String(localized: "settings.background.none", defaultValue: "Ninguno")
        }
    }
}
