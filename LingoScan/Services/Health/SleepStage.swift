/// Valor de una muestra de sueño de Apple Salud, ya traducido (T-33).
enum SleepStage: Sendable, Hashable {
    case inBed
    case asleepUnspecified
    case core
    case deep
    case rem
    case awake

    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem: true
        case .inBed, .awake: false
        }
    }

    /// Etapa concreta (Apple Watch con watchOS 9 o posterior).
    var isStage: Bool { self == .core || self == .deep || self == .rem }
}
