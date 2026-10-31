/// Banda de un valor de glucosa según `ReportConfiguration`. Informativa, no médica.
public enum GlucoseBand: String, Sendable, Hashable, Codable, CaseIterable {
    case low
    case inRange = "in_range"
    case high
    case veryHigh = "very_high"

    public init(valueMgdl value: Int, configuration: ReportConfiguration) {
        if value < configuration.rangeLow {
            self = .low
        } else if value <= configuration.rangeHigh {
            self = .inRange
        } else if value <= configuration.veryHighThreshold {
            self = .high
        } else {
            self = .veryHigh
        }
    }
}
