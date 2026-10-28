import Foundation

/// Atajos de la longitud visible de la curva en Hoy (chips 3 h / 6 h / 12 h / 24 h, como la referencia de Lingo).
/// La longitud visible es continua (pellizco); un chip solo aparece seleccionado cuando coincide con ella.
enum TodayPeriod: Int, Sendable, Hashable, CaseIterable, Identifiable {
    case threeHours = 3
    case sixHours = 6
    case twelveHours = 12
    case twentyFourHours = 24

    /// Clave de `AppStorage` con las horas del último chip elegido.
    static let storageKey = "today.periodHours"

    /// Tolerancia para considerar que la longitud visible coincide con un chip.
    static let matchTolerance: TimeInterval = 60

    var id: Int { rawValue }

    var hours: Int { rawValue }

    var duration: TimeInterval { TimeInterval(rawValue) * 3_600 }

    /// Chip que coincide con `length` (±1 min), o `nil` con un zoom libre.
    static func matching(_ length: TimeInterval) -> TodayPeriod? {
        allCases.first { abs($0.duration - length) <= matchTolerance }
    }

    var title: String {
        switch self {
        case .threeHours: String(localized: "today.period.3h", defaultValue: "3 h")
        case .sixHours: String(localized: "today.period.6h", defaultValue: "6 h")
        case .twelveHours: String(localized: "today.period.12h", defaultValue: "12 h")
        case .twentyFourHours: String(localized: "today.period.24h", defaultValue: "24 h")
        }
    }
}
