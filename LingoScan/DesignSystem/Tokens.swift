import SwiftUI

/// Tokens de diseño: espaciado sobre rejilla de 8 pt, radios y colores semánticos.
///
/// Los colores viven en `Assets.xcassets` con variantes claro/oscuro y de contraste aumentado.
/// El rojo no está aquí a propósito: se reserva a errores de la app, nunca a valores de glucosa.
enum Tokens {
    enum Spacing {
        static let xxs = 4.0
        static let xs = 8.0
        static let sm = 16.0
        static let md = 24.0
        static let lg = 32.0
        static let xl = 48.0
    }

    enum Radius {
        static let card = 16.0
    }

    enum Palette {
        /// Verde apagado: glucosa dentro del rango de referencia.
        static let inRange = Color(.inRange)
        /// Ámbar: glucosa fuera del rango de referencia.
        static let outOfRange = Color(.outOfRange)
        /// Ámbar oscuro: dato atrasado (sin trama válida reciente).
        static let stale = Color(.stale)
        /// Gris: huecos sin datos y calentamiento.
        static let gap = Color(.gap)
        /// Rojo del sistema: solo para errores de la app (autenticación fallida, no compatible).
        static let error = Color.red
        /// Curva por encima de la referencia alta (cálido).
        static let high = Color.red
        /// Curva por debajo de la referencia baja (frío).
        static let low = Color.blue
    }

    /// Paleta "Studio" (port de JPLights): superficies y texto sobre el fondo animado. Se resuelve por esquema de
    /// color (T-30, D-33): estudio oscuro en oscuro y una variante clara con la misma jerarquía en claro.
    ///
    /// Contraste en claro sobre `card` (blanco): `textPrimary` ≈ 17:1 y `textSecondary` ≈ 5,4:1 (AA);
    /// `textTertiary` ≈ 3,3:1, igual que en oscuro solo para texto auxiliar o grande; `accent` ≈ 4,6:1.
    enum Studio {
        static let background = adaptive(light: UIColor(red: 0.972, green: 0.966, blue: 0.954, alpha: 1),
                                         dark: UIColor(red: 0.030, green: 0.031, blue: 0.038, alpha: 1))
        static let card = adaptive(light: .white,
                                   dark: UIColor(red: 0.075, green: 0.078, blue: 0.092, alpha: 1))
        static let raised = adaptive(light: UIColor(red: 0.930, green: 0.928, blue: 0.922, alpha: 1),
                                     dark: UIColor(red: 0.118, green: 0.122, blue: 0.142, alpha: 1))
        static let stroke = adaptive(light: UIColor(white: 0, alpha: 0.08), dark: UIColor(white: 1, alpha: 0.09))
        /// Contorno de las superficies opacas de vidrio (Reducir transparencia) y de miniaturas.
        static let edge = adaptive(light: UIColor(white: 0, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.14))
        /// Sombra de las cards en claro (en oscuro no hay sombra: la separa el filo de luz).
        static let shadow = adaptive(light: UIColor(white: 0, alpha: 0.07), dark: .clear)

        static let textPrimary = adaptive(light: UIColor(white: 0.10, alpha: 1), dark: UIColor(white: 0.96, alpha: 1))
        static let textSecondary = adaptive(light: UIColor(white: 0.42, alpha: 1), dark: UIColor(white: 0.64, alpha: 1))
        static let textTertiary = adaptive(light: UIColor(white: 0.55, alpha: 1), dark: UIColor(white: 0.43, alpha: 1))

        /// Acento de selección (ámbar suave de JPLights; en claro, más oscuro para contraste). Nunca se usa para
        /// valores de glucosa.
        static let accent = adaptive(light: UIColor(red: 0.66, green: 0.40, blue: 0.04, alpha: 1),
                                     dark: UIColor(red: 1.00, green: 0.71, blue: 0.29, alpha: 1))

        /// Opacidad de las superficies sólidas: dejan pasar apenas el fondo (≈ 8 %);
        /// con Reducir transparencia son opacas del todo.
        static func cardOpacity(reduceTransparency: Bool) -> Double { reduceTransparency ? 1 : 0.92 }
        /// Tope del tinte del vidrio (el color va en el tinte, nunca en un relleno sólido).
        static let glassTintCap = 0.32

        /// Color que resuelve claro u oscuro según el entorno (SwiftUI pasa su esquema a los `UIColor` dinámicos).
        private static func adaptive(light: UIColor, dark: UIColor) -> Color {
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
        }
    }

    /// Rango de referencia de la gráfica. No es un objetivo médico y se muestra como tal.
    enum ReferenceRange {
        static let lower = 70
        static let upper = 180
        static let bounds = lower...upper
    }
}
