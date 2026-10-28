/// Velocidad de cambio de la glucosa y episodios de subida o bajada rápida (T-23). Informativo, no médico.
///
/// **Pendiente**: regresión lineal por mínimos cuadrados (valor frente a minutos) sobre las lecturas de una
/// ventana deslizante que termina en cada lectura (`window`, 15 min por defecto). Se eligió la regresión y no
/// la diferencia entre medias de los extremos porque usa todas las lecturas y amortigua mejor el ruido de ±3 mg/dL.
/// Una ventana solo cuenta si tiene al menos `minimumSamples` lecturas, abarca al menos `minimumSpan` y no
/// tiene huecos internos de más de `maxGap` (sin interpolar, como el resto de la app).
///
/// **Episodios**: cada ventana con `|pendiente| ≥ threshold` marca su intervalo con la dirección del signo; las
/// ventanas marcadas de la misma dirección que se solapan o se tocan se fusionan. Después cada episodio se
/// recorta a la excursión real: en una subida, del último mínimo anterior al máximo al primer máximo; en una bajada, del
/// máximo al mínimo. Se descartan los episodios recortados de menos de `minimumDuration` (10 min).
public enum RateOfChange {
    /// Umbral por defecto en mg/dL por minuto.
    public static let defaultThreshold = 2.0
    /// Ventana por defecto (segundos).
    public static let defaultWindow: Double = 900
    /// Duración mínima de un episodio (segundos).
    public static let minimumDuration: Int64 = 600
    /// Lecturas mínimas en una ventana para calcular su pendiente.
    public static let minimumSamples = 8
    /// Hueco máximo entre lecturas contiguas dentro de una ventana (segundos).
    public static let maxGap: Int64 = 300

    /// Pendiente por regresión lineal simple en mg/dL por minuto; `nil` con menos de 2 instantes distintos.
    public static func slope(of samples: [BasicStats.Sample]) -> Double? {
        guard samples.count >= 2, let origin = samples.map(\.measuredAt.epochSeconds).min() else { return nil }
        let xs = samples.map { Double($0.measuredAt.epochSeconds - origin) / 60 }
        let ys = samples.map { Double($0.valueMgdl) }
        let n = Double(samples.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for (x, y) in zip(xs, ys) {
            sxy += (x - meanX) * (y - meanY)
            sxx += (x - meanX) * (x - meanX)
        }
        return sxx > 0 ? sxy / sxx : nil
    }

    /// Episodios de cambio rápido en orden cronológico.
    /// - Parameters:
    ///   - samples: lecturas válidas; el orden da igual y las repetidas del mismo instante cuentan una vez.
    ///   - threshold: pendiente mínima (en valor absoluto) en mg/dL por minuto.
    ///   - window: longitud de la ventana deslizante en segundos.
    public static func events(
        in samples: [BasicStats.Sample],
        threshold: Double = defaultThreshold,
        window: Double = defaultWindow
    ) -> [RateEvent] {
        var seen = Set<UTCInstant>()
        let sorted = samples.sorted { $0.measuredAt < $1.measuredAt }.filter { seen.insert($0.measuredAt).inserted }
        guard sorted.count >= minimumSamples, threshold > 0, window > 0 else { return [] }
        let windowSeconds = Int64(window.rounded())
        let minimumSpan = min(minimumDuration, windowSeconds)

        // Intervalos (índices de lectura) de ventanas marcadas, ya fusionados por dirección.
        var spans: [(first: Int, last: Int, direction: RateEvent.Direction)] = []
        var lower = 0
        for upper in sorted.indices {
            let end = sorted[upper].measuredAt.epochSeconds
            while end - sorted[lower].measuredAt.epochSeconds > windowSeconds { lower += 1 }
            let slice = sorted[lower...upper]
            guard slice.count >= minimumSamples,
                  end - sorted[lower].measuredAt.epochSeconds >= minimumSpan,
                  !hasGap(sorted, lower, upper),
                  let slope = slope(of: Array(slice)),
                  abs(slope) >= threshold
            else { continue }
            let direction: RateEvent.Direction = slope > 0 ? .rising : .falling
            if let last = spans.last, last.direction == direction, lower <= last.last {
                spans[spans.count - 1].last = upper
            } else {
                spans.append((lower, upper, direction))
            }
        }

        return spans.compactMap { span in
            trimmed(sorted, first: span.first, last: span.last, direction: span.direction)
        }
    }

    private static func hasGap(_ sorted: [BasicStats.Sample], _ lower: Int, _ upper: Int) -> Bool {
        guard upper > lower else { return false }
        for index in (lower + 1)...upper
        where sorted[index].measuredAt.epochSeconds - sorted[index - 1].measuredAt.epochSeconds > maxGap {
            return true
        }
        return false
    }

    /// Recorta el episodio a la excursión: subida del mínimo al máximo posterior; bajada del máximo al mínimo posterior.
    private static func trimmed(
        _ sorted: [BasicStats.Sample], first: Int, last: Int, direction: RateEvent.Direction
    ) -> RateEvent? {
        let range = first...last
        let rising = direction == .rising
        // Extremo final: el máximo (subida) o el mínimo (bajada); en empate, el primero (donde se alcanza).
        guard let endIndex = range.max(by: { a, b in
            rising ? sorted[a].valueMgdl < sorted[b].valueMgdl : sorted[a].valueMgdl > sorted[b].valueMgdl
        }) else { return nil }
        // Extremo inicial antes del final: el mínimo (subida) o el máximo (bajada); en empate, el último.
        guard let startIndex = (first...endIndex).max(by: { a, b in
            rising ? sorted[a].valueMgdl >= sorted[b].valueMgdl : sorted[a].valueMgdl <= sorted[b].valueMgdl
        }) else { return nil }
        let start = sorted[startIndex], end = sorted[endIndex]
        let seconds = end.measuredAt.epochSeconds - start.measuredAt.epochSeconds
        guard seconds >= minimumDuration else { return nil }
        return RateEvent(
            start: start.measuredAt,
            end: end.measuredAt,
            direction: direction,
            slopePerMinute: Double(end.valueMgdl - start.valueMgdl) / (Double(seconds) / 60),
            from: start.valueMgdl,
            to: end.valueMgdl
        )
    }
}
