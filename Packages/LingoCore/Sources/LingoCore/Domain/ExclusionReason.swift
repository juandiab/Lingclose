/// `eligibility.reason` (contrato §5.2).
public enum ExclusionReason: String, Sendable, Codable, Hashable, CaseIterable {
    case deleted
    case synthetic
    case qualityFlag = "quality_flag"
    case warmUp = "warm_up"
    case outOfRange = "out_of_range"
    case decoderError = "decoder_error"
    case duplicate
    case other

    /// Rango de precedencia del contrato §5.2 (mayor gana):
    /// `deleted > synthetic > quality_flag > warm_up > out_of_range > decoder_error > duplicate > other`.
    public var precedence: Int {
        switch self {
        case .deleted: 8
        case .synthetic: 7
        case .qualityFlag: 6
        case .warmUp: 5
        case .outOfRange: 4
        case .decoderError: 3
        case .duplicate: 2
        case .other: 1
        }
    }

    /// Exclusiones que otra ruta puede levantar (contrato §5.2 "Levantar una exclusión").
    public var isLiftableByAnotherRoute: Bool {
        switch self {
        case .qualityFlag, .warmUp, .outOfRange, .decoderError: true
        case .deleted, .synthetic, .duplicate, .other: false
        }
    }
}
