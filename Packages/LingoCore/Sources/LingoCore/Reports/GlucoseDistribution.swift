/// Distribución de lecturas válidas de un período: percentiles, media, desviación y minutos cubiertos.
/// Informativa, no médica. Como `BasicStats`, solo cuenta lecturas válidas y una por instante; no interpola huecos.
/// Es la base de "Sugerir rango" (Ajustes): los percentiles 5 y 95 de las lecturas propias.
public struct GlucoseDistribution: Sendable, Hashable {
    /// Lecturas válidas usadas (una por instante).
    public let count: Int
    /// Media en mg/dL; `nil` sin lecturas.
    public let mean: Double?
    /// Desviación estándar muestral (n − 1) en mg/dL; `nil` con menos de 2 lecturas.
    public let standardDeviation: Double?
    public let minimum: Int?
    public let maximum: Int?
    /// Minutos distintos del reloj con al menos una lectura válida. Mide cuánto tiempo real hay detrás de la
    /// distribución sin depender del intervalo nominal.
    public let coveredMinutes: Int
    public let first: UTCInstant?
    public let last: UTCInstant?
    private let sortedValues: [Int]

    public init(samples: [BasicStats.Sample]) {
        var seen = Set<UTCInstant>()
        let unique = samples.filter { seen.insert($0.measuredAt).inserted }
        let values = unique.map(\.valueMgdl).sorted()
        sortedValues = values
        count = values.count
        minimum = values.first
        maximum = values.last
        coveredMinutes = Set(unique.map { $0.measuredAt.epochSeconds / 60 }).count
        first = unique.map(\.measuredAt).min()
        last = unique.map(\.measuredAt).max()
        if values.isEmpty {
            mean = nil
            standardDeviation = nil
        } else {
            let n = Double(values.count)
            let average = Double(values.reduce(0, +)) / n
            mean = average
            standardDeviation = values.count < 2 ? nil
                : (values.reduce(0.0) { $0 + (Double($1) - average) * (Double($1) - average) } / (n - 1)).squareRoot()
        }
    }

    /// Desde lecturas completas: solo glucosa, no borradas, no sintéticas, elegibles y con valor.
    public init(readings: [GlucoseReading]) {
        self.init(samples: readings.compactMap { reading -> BasicStats.Sample? in
            guard reading.analyte == .glucose, !reading.deleted, !reading.synthetic, reading.eligibility.isEligible,
                  let value = reading.value else { return nil }
            return BasicStats.Sample(measuredAt: reading.measuredAt, valueMgdl: value)
        })
    }

    public var coveredHours: Double { Double(coveredMinutes) / 60 }

    /// Percentil `p` (0…100) con interpolación lineal entre valores vecinos (tipo 7 de Hyndman–Fan, el de
    /// hojas de cálculo y NumPy). `nil` sin lecturas o con `p` fuera de 0…100.
    public func percentile(_ p: Double) -> Double? {
        guard !sortedValues.isEmpty, (0...100).contains(p) else { return nil }
        if sortedValues.count == 1 { return Double(sortedValues[0]) }
        let position = p / 100 * Double(sortedValues.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sortedValues.count - 1)
        let fraction = position - Double(lower)
        return Double(sortedValues[lower]) + fraction * Double(sortedValues[upper] - sortedValues[lower])
    }

    public var median: Double? { percentile(50) }
}
