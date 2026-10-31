/// Los cinco tramos del consenso internacional de tiempo en rango (Battelino et al., 2019), en mg/dL:
/// < 54, 54–69, 70–180, 181–250 y > 250. Son fijos: no dependen del rango personal del usuario.
enum MedicalRangeBand: Int, Sendable, Hashable, CaseIterable {
    case veryLow, low, target, high, veryHigh

    init(mgdl value: Int) {
        switch value {
        case ..<54: self = .veryLow
        case 54..<70: self = .low
        case 70...180: self = .target
        case 181...250: self = .high
        default: self = .veryHigh
        }
    }
}
