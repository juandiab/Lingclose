/// Parámetros de un cálculo de reportes (T-27a). Informativos, no objetivos médicos.
///
/// Bandas: bajo `< rangeLow`; en rango `rangeLow…rangeHigh`; alto `> rangeHigh` y `≤ veryHighThreshold`;
/// muy alto `> veryHighThreshold`. La noche va de `nightStartMinute` a `nightEndMinute` (minutos desde la
/// medianoche local); si el inicio es mayor que el fin, cruza la medianoche.
public struct ReportConfiguration: Sendable, Hashable, Codable {
    public static let defaultVeryHighThreshold = 250
    public static let defaultNightStartMinute = 23 * 60
    public static let defaultNightEndMinute = 7 * 60
    public static let `default` = ReportConfiguration()

    public let rangeLow: Int
    public let rangeHigh: Int
    /// Nunca menor que `rangeHigh`.
    public let veryHighThreshold: Int
    public let nightStartMinute: Int
    public let nightEndMinute: Int
    /// Pendiente mínima (mg/dL por minuto, valor absoluto) de un cambio rápido (`RateOfChange.events`).
    public let fastChangeThreshold: Double

    public init(
        range: ClosedRange<Int> = BasicStats.defaultRange,
        veryHighThreshold: Int = ReportConfiguration.defaultVeryHighThreshold,
        nightStartMinute: Int = ReportConfiguration.defaultNightStartMinute,
        nightEndMinute: Int = ReportConfiguration.defaultNightEndMinute,
        fastChangeThreshold: Double = RateOfChange.defaultThreshold
    ) {
        rangeLow = range.lowerBound
        rangeHigh = range.upperBound
        self.veryHighThreshold = max(veryHighThreshold, range.upperBound)
        self.nightStartMinute = min(max(nightStartMinute, 0), 1439)
        self.nightEndMinute = min(max(nightEndMinute, 0), 1439)
        self.fastChangeThreshold = fastChangeThreshold
    }

    public var range: ClosedRange<Int> { rangeLow...rangeHigh }

    enum CodingKeys: String, CodingKey {
        case rangeLow = "range_low"
        case rangeHigh = "range_high"
        case veryHighThreshold = "very_high_threshold"
        case nightStartMinute = "night_start_minute"
        case nightEndMinute = "night_end_minute"
        case fastChangeThreshold = "fast_change_threshold"
    }
}
