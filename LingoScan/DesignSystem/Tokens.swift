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

    /// Paleta "Studio" (estudio oscuro, port de JPLights): superficies y texto sobre el fondo animado.
    /// Solo se usa con fondo animado, que fuerza el modo oscuro; con "Ninguno" mandan los colores del sistema.
    enum Studio {
        static let background = Color(red: 0.030, green: 0.031, blue: 0.038)
        static let card = Color(red: 0.075, green: 0.078, blue: 0.092)
        static let raised = Color(red: 0.118, green: 0.122, blue: 0.142)
        static let stroke = Color.white.opacity(0.09)

        static let textPrimary = Color(white: 0.96)
        static let textSecondary = Color(white: 0.64)
        static let textTertiary = Color(white: 0.43)

        /// Acento de selección (ámbar suave de JPLights). Nunca se usa para valores de glucosa.
        static let accent = Color(red: 1.00, green: 0.71, blue: 0.29)

        /// Opacidad de las superficies sólidas: dejan pasar apenas el fondo (≈ 8 %);
        /// con Reducir transparencia son opacas del todo.
        static func cardOpacity(reduceTransparency: Bool) -> Double { reduceTransparency ? 1 : 0.92 }
        /// Tope del tinte del vidrio (el color va en el tinte, nunca en un relleno sólido).
        static let glassTintCap = 0.32
    }

    /// Rango de referencia de la gráfica. No es un objetivo médico y se muestra como tal.
    enum ReferenceRange {
        static let lower = 70
        static let upper = 180
        static let bounds = lower...upper
    }
}
