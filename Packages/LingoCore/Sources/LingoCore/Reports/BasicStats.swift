/// Métricas básicas de un período (T-12a): tiempo en rango, media y desviación estándar.
/// Informativas, no médicas. Solo cuentan lecturas válidas: los huecos no se interpolan, así que el tiempo en
/// rango es la fracción de lecturas válidas dentro del rango (no de minutos del reloj). `coverage` dice cuánto
/// del período tiene datos.
public struct BasicStats: Sendable, Hashable {
    /// Una lectura válida: instante y valor en mg/dL.
    public struct Sample: Sendable, Hashable {
        public let measuredAt: UTCInstant
        public let valueMgdl: Int

        public init(measuredAt: UTCInstant, valueMgdl: Int) {
            self.measuredAt = measuredAt
            self.valueMgdl = valueMgdl
        }
    }

    /// Rango de referencia por defecto (editable más adelante; no es un objetivo médico).
    public static let defaultRange = 70...180
    /// Intervalo nominal entre lecturas de Lingo.
    public static let nominalIntervalSeconds: Int64 = 60

    /// Lecturas válidas usadas.
    public let count: Int
    /// Media en mg/dL; `nil` sin lecturas.
    public let mean: Double?
    /// Desviación estándar muestral (n − 1) en mg/dL; `nil` con menos de 2 lecturas.
    public let standardDeviation: Double?
    /// Fracción 0…1 de lecturas dentro del rango (ambos extremos incluidos); `nil` sin lecturas.
    public let timeInRange: Double?
    public let range: ClosedRange<Int>
    /// Fracción 0…1 de minutos del período con una lectura; `nil` si no se dio el período.
    public let coverage: Double?

    /// - Parameters:
    ///   - samples: lecturas válidas; el orden da igual. Las repetidas del mismo instante cuentan una sola vez.
    ///   - range: rango de referencia, inclusivo.
    ///   - window: período visible, solo para calcular `coverage` y descartar lecturas fuera de él.
    public init(samples: [Sample], range: ClosedRange<Int> = BasicStats.defaultRange, window: ClosedRange<UTCInstant>? = nil) {
        var seen = Set<UTCInstant>()
        let values: [Int] = samples
            .filter { window?.contains($0.measuredAt) ?? true }
            .filter { seen.insert($0.measuredAt).inserted }
            .map(\.valueMgdl)
        self.range = range
        count = values.count
        if values.isEmpty {
            mean = nil
            standardDeviation = nil
            timeInRange = nil
        } else {
            let n = Double(values.count)
            let average = Double(values.reduce(0, +)) / n
            mean = average
            standardDeviation = values.count < 2 ? nil
                : (values.reduce(0.0) { $0 + (Double($1) - average) * (Double($1) - average) } / (n - 1)).squareRoot()
            timeInRange = Double(values.filter(range.contains).count) / n
        }
        if let window {
            let expected = Double(window.upperBound.epochSeconds - window.lowerBound.epochSeconds) / Double(Self.nominalIntervalSeconds) + 1
            coverage = expected > 0 ? min(1, Double(values.count) / expected) : nil
        } else {
            coverage = nil
        }
    }

    /// Desde lecturas completas: solo glucosa, no borradas, elegibles y con valor (calentamiento y exclusiones fuera).
    public init(readings: [GlucoseReading], range: ClosedRange<Int> = BasicStats.defaultRange, window: ClosedRange<UTCInstant>? = nil) {
        let samples = readings.compactMap { reading -> Sample? in
            guard reading.analyte == .glucose, !reading.deleted, reading.eligibility.isEligible, let value = reading.value
            else { return nil }
            return Sample(measuredAt: reading.measuredAt, valueMgdl: value)
        }
        self.init(samples: samples, range: range, window: window)
    }
}
