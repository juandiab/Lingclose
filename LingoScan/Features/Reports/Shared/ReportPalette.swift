import LingoCore
import SwiftUI

/// Colores de Reportes. Nunca rojo para glucosa: bajo azul, en rango verde apagado, alto ámbar (más intenso si es
/// muy alto). Mejora/empeora usa los mismos tonos, siempre acompañados de flecha y texto.
enum ReportPalette {
    static let low = Tokens.Palette.low
    static let inRange = Tokens.Palette.inRange
    static let high = Tokens.Palette.outOfRange.opacity(0.6)
    static let veryHigh = Tokens.Palette.outOfRange

    static let better = Tokens.Palette.inRange
    static let worse = Tokens.Palette.outOfRange

    /// Bandas de percentiles del perfil por hora (neutras: el color lo dan las zonas).
    static let outerBand = Color.primary.opacity(0.10)
    static let innerBand = Color.primary.opacity(0.24)
    /// Lavado muy tenue de las zonas fuera del rango en las gráficas.
    static let highZone = Tokens.Palette.outOfRange.opacity(0.07)
    static let lowZone = Tokens.Palette.low.opacity(0.07)
    static let referenceStroke = StrokeStyle(lineWidth: 0.75, dash: [3, 3])

    static func color(for band: GlucoseBand) -> Color {
        switch band {
        case .low: low
        case .inRange: inRange
        case .high: high
        case .veryHigh: veryHigh
        }
    }

    /// Color de un valor respecto al rango del usuario.
    static func color(value: Double, configuration: ReportConfiguration) -> Color {
        if value < Double(configuration.rangeLow) { return low }
        if value > Double(configuration.rangeHigh) { return Tokens.Palette.outOfRange }
        return inRange
    }
}
