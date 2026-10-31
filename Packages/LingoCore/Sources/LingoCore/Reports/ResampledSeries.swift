/// Serie remuestreada a intervalos fijos desde `start`: `values[k]` es la media redondeada de las lecturas de
/// `[start + k·intervalo, start + (k+1)·intervalo)`, o `nil` si no hubo ninguna (los huecos no se interpolan).
public struct ResampledSeries: Sendable, Hashable, Codable {
    public let start: UTCInstant
    public let intervalMinutes: Int
    public let values: [Int?]

    public init(start: UTCInstant, intervalMinutes: Int, values: [Int?]) {
        self.start = start
        self.intervalMinutes = intervalMinutes
        self.values = values
    }

    /// Agrupa de `factor` en `factor` intervalos (media de los valores no nulos, redondeada).
    /// Es una aproximación: no pondera por el número de lecturas de cada intervalo.
    public func downsampled(by factor: Int) -> ResampledSeries {
        guard factor > 1 else { return self }
        var result: [Int?] = []
        result.reserveCapacity(values.count / factor + 1)
        var index = 0
        while index < values.count {
            let chunk = values[index..<min(index + factor, values.count)].compactMap { $0 }
            result.append(chunk.isEmpty ? nil : Int((Double(chunk.reduce(0, +)) / Double(chunk.count)).rounded()))
            index += factor
        }
        return ResampledSeries(start: start, intervalMinutes: intervalMinutes * factor, values: result)
    }

    /// Serie de `times`/`values` (ordenados) dentro de `[start, end)`.
    static func make(times: ArraySlice<Int64>, values: ArraySlice<Int>, start: UTCInstant, end: UTCInstant,
                     intervalMinutes: Int) -> ResampledSeries {
        let interval = Int64(intervalMinutes) * 60
        let span = max(0, end.epochSeconds - start.epochSeconds)
        let count = Int((span + interval - 1) / interval)
        var sums = [Int](repeating: 0, count: count)
        var counts = [Int](repeating: 0, count: count)
        for (t, v) in zip(times, values) {
            let k = Int((t - start.epochSeconds) / interval)
            guard k >= 0, k < count else { continue }
            sums[k] += v
            counts[k] += 1
        }
        let out: [Int?] = (0..<count).map { counts[$0] == 0 ? nil : Int((Double(sums[$0]) / Double(counts[$0])).rounded()) }
        return ResampledSeries(start: start, intervalMinutes: intervalMinutes, values: out)
    }

    enum CodingKeys: String, CodingKey {
        case start
        case intervalMinutes = "interval_minutes"
        case values
    }
}
