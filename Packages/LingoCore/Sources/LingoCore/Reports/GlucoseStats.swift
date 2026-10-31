/// Estadísticas de glucosa de una ventana (período, día, semana, franja, noche). Informativas, no médicas.
///
/// Como `BasicStats`: solo lecturas válidas, una por instante, sin interpolar huecos; las fracciones de banda son
/// fracciones de lecturas (0…1). Mínimos: `mean`, `minimum`, `maximum` y las bandas necesitan ≥ 1 lectura;
/// `standardDeviation` y `coefficientOfVariation` (`SD / media`, 0…1) necesitan ≥ 2. `coverage` es la fracción
/// de minutos de la ventana con al menos una lectura (Lingo mide una por minuto); `nil` si no hay ventana.
public struct GlucoseStats: Sendable, Hashable, Codable {
    public let readings: Int
    public let coveredMinutes: Int
    public let coverage: Double?
    public let mean: Double?
    public let standardDeviation: Double?
    public let coefficientOfVariation: Double?
    public let minimum: Int?
    public let maximum: Int?
    public let timeLow: Double?
    public let timeInRange: Double?
    public let timeHigh: Double?
    public let timeVeryHigh: Double?

    public var hasReadings: Bool { readings > 0 }

    /// Igual que `coverage ≥ ReportThresholds.minimumDayCoverage`.
    public var meetsDayCoverage: Bool { (coverage ?? 0) >= ReportThresholds.minimumDayCoverage }

    enum CodingKeys: String, CodingKey {
        case readings
        case coveredMinutes = "covered_minutes"
        case coverage, mean
        case standardDeviation = "sd"
        case coefficientOfVariation = "cv"
        case minimum = "min"
        case maximum = "max"
        case timeLow = "time_low"
        case timeInRange = "time_in_range"
        case timeHigh = "time_high"
        case timeVeryHigh = "time_very_high"
    }

    init(readings: Int, coveredMinutes: Int, coverage: Double?, mean: Double?, standardDeviation: Double?,
         coefficientOfVariation: Double?, minimum: Int?, maximum: Int?, timeLow: Double?, timeInRange: Double?,
         timeHigh: Double?, timeVeryHigh: Double?) {
        self.readings = readings
        self.coveredMinutes = coveredMinutes
        self.coverage = coverage
        self.mean = mean
        self.standardDeviation = standardDeviation
        self.coefficientOfVariation = coefficientOfVariation
        self.minimum = minimum
        self.maximum = maximum
        self.timeLow = timeLow
        self.timeInRange = timeInRange
        self.timeHigh = timeHigh
        self.timeVeryHigh = timeVeryHigh
    }

    /// Acumulador en una pasada. Las lecturas deben llegar en orden de tiempo (para contar minutos distintos).
    struct Accumulator {
        let configuration: ReportConfiguration
        var count = 0
        var sum = 0.0
        var sumOfSquares = 0.0
        var minimum = Int.max
        var maximum = Int.min
        var bands = [0, 0, 0, 0]
        var minutes = 0
        var lastMinute = Int64.min

        init(configuration: ReportConfiguration) { self.configuration = configuration }

        mutating func add(time: Int64, value: Int) {
            count += 1
            let v = Double(value)
            sum += v
            sumOfSquares += v * v
            minimum = Swift.min(minimum, value)
            maximum = Swift.max(maximum, value)
            if value < configuration.rangeLow {
                bands[0] += 1
            } else if value <= configuration.rangeHigh {
                bands[1] += 1
            } else if value <= configuration.veryHighThreshold {
                bands[2] += 1
            } else {
                bands[3] += 1
            }
            let minute = LocalClock.floorDiv(time, 60)
            if minute != lastMinute {
                minutes += 1
                lastMinute = minute
            }
        }

        func stats(windowSeconds: Int64?) -> GlucoseStats {
            let coverage: Double? = windowSeconds.flatMap { seconds in
                seconds > 0 ? ReportRounding.r3(Swift.min(1, Double(minutes) / (Double(seconds) / 60))) : nil
            }
            guard count > 0 else {
                return GlucoseStats(readings: 0, coveredMinutes: 0, coverage: coverage, mean: nil, standardDeviation: nil,
                                    coefficientOfVariation: nil, minimum: nil, maximum: nil, timeLow: nil,
                                    timeInRange: nil, timeHigh: nil, timeVeryHigh: nil)
            }
            let n = Double(count)
            let mean = sum / n
            let sd: Double? = count < 2 ? nil : Swift.max(0, (sumOfSquares - sum * sum / n) / (n - 1)).squareRoot()
            let cv: Double? = sd.flatMap { mean > 0 ? $0 / mean : nil }
            func fraction(_ k: Int) -> Double { ReportRounding.r3(Double(k) / n) }
            return GlucoseStats(
                readings: count, coveredMinutes: minutes, coverage: coverage, mean: ReportRounding.r1(mean),
                standardDeviation: ReportRounding.r1(optional: sd), coefficientOfVariation: ReportRounding.r3(optional: cv),
                minimum: minimum, maximum: maximum, timeLow: fraction(bands[0]), timeInRange: fraction(bands[1]),
                timeHigh: fraction(bands[2]), timeVeryHigh: fraction(bands[3]))
        }
    }
}
