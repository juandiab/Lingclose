import Foundation

/// Tono del fondo según la última lectura y el rango de referencia del usuario.
///
/// Nunca rojo (regla de `Tokens`): alto → ámbar cálido, bajo → azul, en rango → verde-teal;
/// sin lectura, atrasada o sin sensor → neutro tenue.
enum GlucoseBackgroundTone: String, Sendable, CaseIterable {
    case inRange
    case high
    case low
    case neutral

    /// Sin lectura en más de este margen el dato se considera atrasado (igual que `TodayViewModel.staleAfter`).
    static let staleAfter: TimeInterval = 300

    /// - Parameters:
    ///   - value: última lectura elegible (mg/dL), `nil` si no hay.
    ///   - measuredAt: instante de esa lectura.
    ///   - now: reloj actual.
    ///   - low: línea de referencia baja (mg/dL).
    ///   - high: línea de referencia alta (mg/dL).
    static func resolve(value: Int?, measuredAt: Date?, now: Date, low: Int, high: Int) -> GlucoseBackgroundTone {
        guard let value, let measuredAt, now.timeIntervalSince(measuredAt) <= staleAfter else { return .neutral }
        if value < low { return .low }
        if value > high { return .high }
        return .inRange
    }
}
