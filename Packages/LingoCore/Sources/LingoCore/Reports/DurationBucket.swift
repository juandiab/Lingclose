/// Tramo de duración de un ejercicio (minutos). `unspecified` si la marca no tiene duración.
public enum DurationBucket: String, Sendable, Hashable, Codable, CaseIterable {
    case unspecified
    case under30 = "lt_30"
    case from30To60 = "30_60"
    case atLeast60 = "gte_60"

    public init(durationMinutes: Int?) {
        guard let minutes = durationMinutes else { self = .unspecified; return }
        switch minutes {
        case ..<30: self = .under30
        case ..<60: self = .from30To60
        default: self = .atLeast60
        }
    }
}
