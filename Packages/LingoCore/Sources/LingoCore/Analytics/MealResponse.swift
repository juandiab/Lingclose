/// Respuesta de la glucosa a una comida (T-23). Informativa, no médica.
///
/// Se mira de `t0 − 30 min` a `t0 + 3 h` (`t0` = hora de la marca de comida):
/// - `baseline`: media de las lecturas de `[t0 − 15 min, t0)`; sin ninguna, la primera lectura de
///   `[t0, t0 + 5 min]`; sin esa tampoco, no hay respuesta.
/// - `peakValue` / `peakAt`: lectura más alta de `[t0, t0 + 3 h]` (la primera si se repite).
/// - `rise = peakValue − baseline`; `timeToPeak = peakAt − t0`.
/// - `returnedAt`: primera lectura posterior al pico con valor `≤ baseline + 10`; `nil` si no vuelve en 3 h.
/// - `timeAboveHigh`: segundos de `[t0, t0 + 3 h]` por encima de la referencia alta. Cada par de lecturas
///   contiguas separadas ≤ 5 min aporta su intervalo si la primera está por encima (sin interpolar huecos).
/// - `score` 0–100 (informativo; más alto = respuesta más suave):
///   `100 − min(60, max(0, rise − 20) × 0,6) − min(40, max(0, minutosHastaVolver − 60) × 40 / 120)`,
///   redondeado y acotado a 0…100. Si no vuelve en 3 h, la penalización de vuelta es la máxima (40).
///   Ejemplo: +60 mg/dL y vuelta a los 110 min → 100 − 24 − 16,7 ≈ 59.
///
/// No hay respuesta (`nil`) si la última lectura está a menos de 60 min de `t0` (comida reciente o datos
/// cortados) o si en la primera hora (`[t0, t0 + 60 min]`, contando los bordes) hay un hueco de más de 20 min.
public struct MealResponse: Sendable, Hashable {
    /// Ventana de análisis tras la comida (segundos).
    public static let horizon: Int64 = 3 * 3_600
    /// Lecturas previas mínimas consideradas para la línea base (segundos).
    public static let baselineWindow: Int64 = 15 * 60
    /// Datos mínimos tras la comida (segundos).
    public static let minimumFollowUp: Int64 = 60 * 60
    /// Hueco máximo permitido en la primera hora (segundos).
    public static let maxGapFirstHour: Int64 = 20 * 60
    /// Margen sobre la línea base para considerar que la glucosa "volvió" (mg/dL).
    public static let returnMargin = 10.0
    /// Hueco máximo entre lecturas para sumar tiempo sobre la referencia alta (segundos).
    public static let aboveHighMaxGap: Int64 = 300

    public let mealAt: UTCInstant
    /// Línea base en mg/dL.
    public let baseline: Double
    public let peakValue: Int
    public let peakAt: UTCInstant
    /// `peakValue − baseline` en mg/dL (puede ser negativa si la glucosa bajó).
    public let rise: Double
    /// Segundos de `mealAt` a `peakAt`.
    public let timeToPeak: Int64
    public let returnedAt: UTCInstant?
    /// Segundos por encima de la referencia alta en las 3 h.
    public let timeAboveHigh: Int64
    /// Puntuación informativa 0…100.
    public let score: Int

    /// Segundos de `mealAt` a `returnedAt`.
    public var timeToReturn: Int64? { returnedAt.map { $0.epochSeconds - mealAt.epochSeconds } }

    /// - Parameters:
    ///   - mealAt: hora de la comida.
    ///   - samples: lecturas válidas (puede haber más de las necesarias; se filtran). Orden indiferente.
    ///   - highReference: referencia alta en mg/dL para `timeAboveHigh`.
    public init?(mealAt t0: UTCInstant, samples: [BasicStats.Sample], highReference: Int) {
        let t = t0.epochSeconds
        var seen = Set<UTCInstant>()
        let sorted = samples
            .filter { $0.measuredAt.epochSeconds >= t - Self.baselineWindow * 2 && $0.measuredAt.epochSeconds <= t + Self.horizon }
            .sorted { $0.measuredAt < $1.measuredAt }
            .filter { seen.insert($0.measuredAt).inserted }
        let before = sorted.filter { $0.measuredAt.epochSeconds >= t - Self.baselineWindow && $0.measuredAt.epochSeconds < t }
        let after = sorted.filter { $0.measuredAt.epochSeconds >= t }

        guard let last = after.last, last.measuredAt.epochSeconds - t >= Self.minimumFollowUp else { return nil }
        // Huecos de la primera hora, con los bordes t0 y t0 + 60 min.
        var previous = t
        for sample in after where sample.measuredAt.epochSeconds <= t + Self.minimumFollowUp {
            if sample.measuredAt.epochSeconds - previous > Self.maxGapFirstHour { return nil }
            previous = sample.measuredAt.epochSeconds
        }
        if t + Self.minimumFollowUp - previous > Self.maxGapFirstHour { return nil }

        let baseline: Double
        if !before.isEmpty {
            baseline = Double(before.map(\.valueMgdl).reduce(0, +)) / Double(before.count)
        } else if let first = after.first, first.measuredAt.epochSeconds - t <= 300 {
            baseline = Double(first.valueMgdl)
        } else {
            return nil
        }

        guard let peakIndex = after.indices.max(by: { after[$0].valueMgdl < after[$1].valueMgdl }) else { return nil }
        let peak = after[peakIndex]
        let returned = after[(peakIndex + 1)...].first { Double($0.valueMgdl) <= baseline + Self.returnMargin }

        var above: Int64 = 0
        for index in after.indices.dropFirst() {
            let dt = after[index].measuredAt.epochSeconds - after[index - 1].measuredAt.epochSeconds
            if dt <= Self.aboveHighMaxGap, after[index - 1].valueMgdl > highReference { above += dt }
        }

        mealAt = t0
        self.baseline = baseline
        peakValue = peak.valueMgdl
        peakAt = peak.measuredAt
        rise = Double(peak.valueMgdl) - baseline
        timeToPeak = peak.measuredAt.epochSeconds - t
        returnedAt = returned?.measuredAt
        timeAboveHigh = above
        score = Self.score(rise: rise, minutesToReturn: returned.map { Double($0.measuredAt.epochSeconds - t) / 60 })
    }

    /// `100 − min(60, max(0, rise − 20) × 0,6) − min(40, max(0, minutos − 60) × 40 / 120)`; sin vuelta, −40.
    public static func score(rise: Double, minutesToReturn: Double?) -> Int {
        let risePenalty = min(60, max(0, rise - 20) * 0.6)
        let returnPenalty = minutesToReturn.map { min(40, max(0, $0 - 60) * 40 / 120) } ?? 40
        return min(100, max(0, Int((100 - risePenalty - returnPenalty).rounded())))
    }
}
