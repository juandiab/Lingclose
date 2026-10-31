import SwiftUI

/// Colores fijos del PDF para el médico (T-34): papel blanco, tinta oscura y un acento azul sobrio. Nunca dependen del
/// modo claro/oscuro ni del fondo de la app. Los tramos de glucosa siguen la convención del informe AGP.
enum MedicalPDFPalette {
    static let paper = Color.white
    static let ink = Color(red: 0.10, green: 0.13, blue: 0.18)
    static let secondary = Color(red: 0.35, green: 0.40, blue: 0.47)
    static let tertiary = Color(red: 0.55, green: 0.59, blue: 0.65)
    static let hairline = Color(red: 0.84, green: 0.86, blue: 0.89)
    static let zebra = Color(red: 0.965, green: 0.972, blue: 0.982)
    static let tile = Color(red: 0.93, green: 0.95, blue: 0.97)
    static let accent = Color(red: 0.11, green: 0.35, blue: 0.55)

    static func band(_ band: MedicalRangeBand) -> Color {
        switch band {
        case .veryLow: Color(red: 0.62, green: 0.11, blue: 0.17)
        case .low: Color(red: 0.86, green: 0.30, blue: 0.27)
        case .target: Color(red: 0.20, green: 0.62, blue: 0.40)
        case .high: Color(red: 0.96, green: 0.72, blue: 0.20)
        case .veryHigh: Color(red: 0.90, green: 0.46, blue: 0.16)
        }
    }

    static var targetFill: Color { band(.target).opacity(0.14) }
    static var targetLine: Color { band(.target).opacity(0.65) }
}
