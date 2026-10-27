import Foundation

/// Ventana de la curva en Hoy (chips 6 h / 12 h / 24 h, como la referencia de Lingo).
enum TodayPeriod: Int, Sendable, Hashable, CaseIterable, Identifiable {
    case sixHours = 6
    case twelveHours = 12
    case twentyFourHours = 24

    /// Clave de `AppStorage` con las horas del período elegido.
    static let storageKey = "today.periodHours"

    var id: Int { rawValue }

    var hours: Int { rawValue }

    var duration: TimeInterval { TimeInterval(rawValue) * 3_600 }

    /// Separación de las marcas del eje horizontal, en horas.
    var axisStrideHours: Int {
        switch self {
        case .sixHours: 2
        case .twelveHours: 3
        case .twentyFourHours: 4
        }
    }

    var title: String {
        switch self {
        case .sixHours: String(localized: "today.period.6h", defaultValue: "6 h")
        case .twelveHours: String(localized: "today.period.12h", defaultValue: "12 h")
        case .twentyFourHours: String(localized: "today.period.24h", defaultValue: "24 h")
        }
    }

    /// Texto largo para VoiceOver ("las últimas 6 horas").
    var spokenTitle: String {
        String(localized: "today.period.spoken", defaultValue: "últimas \(hours) horas")
    }
}
