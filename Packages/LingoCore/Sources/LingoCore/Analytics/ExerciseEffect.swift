/// Efecto del ejercicio sobre la glucosa (T-23). Informativo, no médico.
///
/// - `before`: media de las lecturas de `[start − 15 min, start)`.
/// - `minAfter` / `minAt`: lectura más baja de `[start, end + 90 min]` (durante el ejercicio y hasta 90 min
///   después del fin; la primera si se repite).
/// - `deltaAt60`: lectura más cercana a `end + 60 min` (a ±5 min como mucho) menos `before`; `nil` sin esa lectura.
/// - `end` es la hora de fin de la marca; sin ella, `start + 30 min`.
///
/// No hay efecto (`nil`) sin lecturas previas o sin ninguna lectura desde `start`.
public struct ExerciseEffect: Sendable, Hashable {
    public static let defaultDuration: Int64 = 30 * 60
    public static let beforeWindow: Int64 = 15 * 60
    public static let afterWindow: Int64 = 90 * 60
    /// Distancia máxima a `end + 60 min` de la lectura usada para `deltaAt60` (segundos).
    public static let deltaTolerance: Int64 = 5 * 60

    public let start: UTCInstant
    public let end: UTCInstant
    /// Media previa en mg/dL.
    public let before: Double
    public let minAfter: Int
    public let minAt: UTCInstant
    /// Valor a los 60 min del fin menos `before` (negativo = bajó).
    public let deltaAt60: Double?

    public init?(start: UTCInstant, end: UTCInstant? = nil, samples: [BasicStats.Sample]) {
        let s = start.epochSeconds
        let e = max(end?.epochSeconds ?? s + Self.defaultDuration, s)
        var seen = Set<UTCInstant>()
        let sorted = samples.sorted { $0.measuredAt < $1.measuredAt }.filter { seen.insert($0.measuredAt).inserted }
        let previous = sorted.filter { $0.measuredAt.epochSeconds >= s - Self.beforeWindow && $0.measuredAt.epochSeconds < s }
        let following = sorted.filter { $0.measuredAt.epochSeconds >= s && $0.measuredAt.epochSeconds <= e + Self.afterWindow }
        guard !previous.isEmpty,
              let lowest = following.min(by: { $0.valueMgdl < $1.valueMgdl })
        else { return nil }

        let before = Double(previous.map(\.valueMgdl).reduce(0, +)) / Double(previous.count)
        let target = e + 3_600
        let at60 = following
            .filter { abs($0.measuredAt.epochSeconds - target) <= Self.deltaTolerance }
            .min { abs($0.measuredAt.epochSeconds - target) < abs($1.measuredAt.epochSeconds - target) }

        self.start = start
        self.end = UTCInstant(epochSeconds: e)
        self.before = before
        minAfter = lowest.valueMgdl
        minAt = lowest.measuredAt
        deltaAt60 = at60.map { Double($0.valueMgdl) - before }
    }
}
