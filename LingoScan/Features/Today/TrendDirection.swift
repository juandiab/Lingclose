import Foundation

/// Tendencia de Juggluco/PROTOCOLO_LINGO §3: 1 bajando rápido … 5 subiendo rápido; 0 o nil, desconocida.
enum TrendDirection: Int, Sendable, Hashable {
    case fallingFast = 1
    case falling = 2
    case steady = 3
    case rising = 4
    case risingFast = 5

    init?(rawTrend: Int?) {
        guard let rawTrend, let direction = TrendDirection(rawValue: rawTrend) else { return nil }
        self = direction
    }

    var systemImage: String {
        switch self {
        case .fallingFast: "arrow.down"
        case .falling: "arrow.down.right"
        case .steady: "arrow.right"
        case .rising: "arrow.up.right"
        case .risingFast: "arrow.up"
        }
    }

    var title: String {
        switch self {
        case .fallingFast: String(localized: "today.trend.fallingFast", defaultValue: "bajando rápido")
        case .falling: String(localized: "today.trend.falling", defaultValue: "bajando")
        case .steady: String(localized: "today.trend.steady", defaultValue: "estable")
        case .rising: String(localized: "today.trend.rising", defaultValue: "subiendo")
        case .risingFast: String(localized: "today.trend.risingFast", defaultValue: "subiendo rápido")
        }
    }

    /// Texto cuando la tendencia no se conoce.
    static var unknownTitle: String {
        String(localized: "today.trend.unknown", defaultValue: "tendencia desconocida")
    }
}
