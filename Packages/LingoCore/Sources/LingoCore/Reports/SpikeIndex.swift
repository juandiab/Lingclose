/// Índice de pico (T-11b): área de la curva por encima de un umbral (por defecto 140 mg/dL), en mg/dL·min,
/// dividida por 10 y redondeada. Informativo, no médico; no es el "Lingo Count" propietario de Abbott.
///
/// Un pico va de un cruce ascendente del umbral al siguiente cruce descendente (los cruces se interpolan
/// linealmente entre dos lecturas contiguas). Entre dos lecturas separadas por más de `maxGap` no se
/// interpola: un pico abierto se cierra en su última lectura y uno nuevo se abre en la primera tras el hueco.
public enum SpikeIndex {
    /// Umbral por defecto en mg/dL.
    public static let defaultThreshold = 140
    /// Separación máxima entre lecturas contiguas para considerarlas parte del mismo tramo (segundos).
    public static let defaultMaxGapSeconds: Int64 = 120
    /// El área en mg/dL·min se divide por este divisor para dar el índice.
    public static let divisor = 10.0

    public struct Spike: Sendable, Hashable {
        /// Inicio del pico (cruce ascendente o primera lectura tras un hueco).
        public let start: UTCInstant
        /// Fin del pico (cruce descendente o última lectura antes de un hueco o del final de los datos).
        public let end: UTCInstant
        /// Instante de la lectura más alta.
        public let peakAt: UTCInstant
        public let peakValue: Int
        /// Área sobre el umbral en mg/dL·min.
        public let areaMgdlMin: Double
        /// `round(area / 10)`.
        public var index: Int { Int((areaMgdlMin / SpikeIndex.divisor).rounded()) }
    }

    /// - Parameters:
    ///   - samples: lecturas válidas; el orden da igual y las repetidas del mismo instante cuentan una vez.
    ///   - threshold: umbral en mg/dL; una lectura igual al umbral no está "por encima".
    /// - Returns: picos con área mayor que 0, en orden cronológico.
    public static func spikes(
        in samples: [BasicStats.Sample],
        threshold: Int = defaultThreshold,
        maxGapSeconds: Int64 = defaultMaxGapSeconds
    ) -> [Spike] {
        var seen = Set<UTCInstant>()
        let sorted = samples.sorted { $0.measuredAt < $1.measuredAt }.filter { seen.insert($0.measuredAt).inserted }
        let limit = Double(threshold)

        var result: [Spike] = []
        var open: Builder?

        func close(at end: Double) {
            if let builder = open, let spike = builder.finish(end: end) { result.append(spike) }
            open = nil
        }

        for (offset, sample) in sorted.enumerated() {
            let time = Double(sample.measuredAt.epochSeconds)
            let value = Double(sample.valueMgdl)
            let above = value > limit
            guard offset > 0 else {
                if above { open = Builder(start: time, peakAt: time, peakValue: sample.valueMgdl) }
                continue
            }
            let previous = sorted[offset - 1]
            let previousTime = Double(previous.measuredAt.epochSeconds)
            let previousValue = Double(previous.valueMgdl)
            let dt = time - previousTime
            if sample.measuredAt.epochSeconds - previous.measuredAt.epochSeconds > maxGapSeconds {
                // Hueco: sin interpolar.
                close(at: previousTime)
                if above { open = Builder(start: time, peakAt: time, peakValue: sample.valueMgdl) }
                continue
            }
            let previousAbove = previousValue > limit
            switch (previousAbove, above) {
            case (true, true):
                open?.addArea(((previousValue - limit) + (value - limit)) / 2 * dt / 60)
                open?.see(time: time, value: sample.valueMgdl)
            case (true, false):
                let excess = previousValue - limit
                let fraction = excess / (previousValue - value)
                open?.addArea(excess * fraction * dt / 60 / 2)
                close(at: previousTime + fraction * dt)
            case (false, true):
                let excess = value - limit
                let fraction = (limit - previousValue) / (value - previousValue)
                var builder = Builder(start: previousTime + fraction * dt, peakAt: time, peakValue: sample.valueMgdl)
                builder.addArea(excess * (1 - fraction) * dt / 60 / 2)
                open = builder
            case (false, false):
                break
            }
        }
        if let last = sorted.last { close(at: Double(last.measuredAt.epochSeconds)) }
        return result
    }

    private struct Builder {
        var start: Double
        var peakAt: Double
        var peakValue: Int
        var area = 0.0

        init(start: Double, peakAt: Double, peakValue: Int) {
            self.start = start
            self.peakAt = peakAt
            self.peakValue = peakValue
        }

        mutating func addArea(_ value: Double) { area += value }

        mutating func see(time: Double, value: Int) {
            if value > peakValue { peakValue = value; peakAt = time }
        }

        func finish(end: Double) -> Spike? {
            guard area > 0 else { return nil }
            return Spike(
                start: UTCInstant(epochSeconds: Int64(start.rounded())),
                end: UTCInstant(epochSeconds: Int64(end.rounded())),
                peakAt: UTCInstant(epochSeconds: Int64(peakAt)),
                peakValue: peakValue,
                areaMgdlMin: area)
        }
    }
}
