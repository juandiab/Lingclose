import LingoCore

extension AlertKind: @retroactive Identifiable {
    public var id: String { rawValue }

    var settingsTitle: String {
        switch self {
        case .high: String(localized: "alerts.kind.high", defaultValue: "Alta")
        case .low: String(localized: "alerts.kind.low", defaultValue: "Baja")
        case .risingFast: String(localized: "alerts.kind.risingFast", defaultValue: "Subida rápida")
        case .fallingFast: String(localized: "alerts.kind.fallingFast", defaultValue: "Bajada rápida")
        case .noData: String(localized: "alerts.kind.noData", defaultValue: "Sin datos")
        }
    }

    var systemImage: String {
        switch self {
        case .high: "arrow.up.to.line"
        case .low: "arrow.down.to.line"
        case .risingFast: "arrow.up.right"
        case .fallingFast: "arrow.down.right"
        case .noData: "antenna.radiowaves.left.and.right.slash"
        }
    }
}
