/// Tramo de carbohidratos de una comida (gramos). `unknown` si la marca no tiene carbohidratos.
public enum CarbBucket: String, Sendable, Hashable, Codable, CaseIterable {
    case unknown
    case under20 = "lt_20"
    case from20To45 = "20_45"
    case from45To75 = "45_75"
    case atLeast75 = "gte_75"

    public init(carbsG: Double?) {
        guard let carbs = carbsG else { self = .unknown; return }
        switch carbs {
        case ..<20: self = .under20
        case ..<45: self = .from20To45
        case ..<75: self = .from45To75
        default: self = .atLeast75
        }
    }
}
