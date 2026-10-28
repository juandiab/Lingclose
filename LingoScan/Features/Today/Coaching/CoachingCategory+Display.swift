import LingoCore

extension CoachingCategory {
    /// Símbolo de cada familia de consejo en la tarjeta "Qué hacer".
    var systemImage: String {
        switch self {
        case .move: "figure.walk"
        case .hydrate: "drop"
        case .food: "fork.knife"
        case .rest: "moon.zzz"
        case .wait: "clock"
        case .check: "checklist"
        }
    }
}
