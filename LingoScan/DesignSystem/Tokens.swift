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

    /// Rango de referencia de la gráfica. No es un objetivo médico y se muestra como tal.
    enum ReferenceRange {
        static let lower = 70
        static let upper = 180
        static let bounds = lower...upper
    }
}
