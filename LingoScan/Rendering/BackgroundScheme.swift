import SwiftUI

/// Variante del fondo animado según el esquema de color efectivo de la app (T-30).
enum BackgroundScheme: Sendable, Equatable {
    case dark
    case light

    init(_ colorScheme: ColorScheme) {
        self = colorScheme == .light ? .light : .dark
    }

    /// 0 = oscuro, 1 = claro (valor del uniform que el engine interpola en el cambio).
    var lightness: Float { self == .light ? 1 : 0 }

    /// Color de estudio sRGB (0–1) de la variante: fundidos entre renderers, color de borrado y ranura.
    var studioColor: SIMD3<Float> {
        switch self {
        case .dark: SIMD3(repeating: 10.0 / 255)
        case .light: BackgroundPalette.Light.base
        }
    }
}
