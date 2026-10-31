import HealthKit

/// Grupo sanguíneo de Apple Salud para el reporte en PDF para el médico (T-34). `rawValue` es el texto clínico
/// ("A+", "O−"); `notSet` no existe: sin dato, el campo queda `nil`.
enum BloodTypeSummary: String, Sendable, Equatable, CaseIterable {
    case aPositive = "A+"
    case aNegative = "A−"
    case bPositive = "B+"
    case bNegative = "B−"
    case abPositive = "AB+"
    case abNegative = "AB−"
    case oPositive = "O+"
    case oNegative = "O−"

    init?(_ type: HKBloodType) {
        switch type {
        case .aPositive: self = .aPositive
        case .aNegative: self = .aNegative
        case .bPositive: self = .bPositive
        case .bNegative: self = .bNegative
        case .abPositive: self = .abPositive
        case .abNegative: self = .abNegative
        case .oPositive: self = .oPositive
        case .oNegative: self = .oNegative
        case .notSet: return nil
        @unknown default: return nil
        }
    }
}
