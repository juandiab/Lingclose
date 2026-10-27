import SwiftUI

/// Tokens de diseño: colores semánticos y espaciado sobre rejilla de 8 pt.
enum Tokens {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 16
        static let md: CGFloat = 24
        static let lg: CGFloat = 32
        static let xl: CGFloat = 48
    }

    enum Palette {
        /// Glucosa dentro del rango objetivo.
        static let inRange = Color.green
        /// Glucosa por encima del rango.
        static let high = Color.orange
        /// Glucosa por debajo del rango.
        static let low = Color.red
        /// Dato obsoleto o no disponible.
        static let stale = Color.secondary
    }
}
