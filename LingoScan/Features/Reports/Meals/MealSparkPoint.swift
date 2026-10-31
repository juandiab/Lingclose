import LingoCore

/// Un punto de la mini-curva de una comida: minutos desde la comida y valor remuestreado.
struct MealSparkPoint: Identifiable, Hashable, Sendable {
    let minute: Int
    let value: Int

    var id: Int { minute }

    /// Tramo `from…from + minutes` de la serie del período (sin interpolar huecos).
    static func curve(series: ResampledSeries, from start: UTCInstant, minutes: Int) -> [MealSparkPoint] {
        let interval = Int64(series.intervalMinutes) * 60
        guard interval > 0 else { return [] }
        let offset = start.epochSeconds - series.start.epochSeconds
        let first = Int((offset + interval - 1) / interval)
        let last = Int((offset + Int64(minutes) * 60) / interval)
        let lower = max(0, first)
        guard lower <= last else { return [] }
        var points: [MealSparkPoint] = []
        for index in lower...last where index < series.values.count {
            guard let value = series.values[index] else { continue }
            let minute = Int((Int64(index) * interval - offset) / 60)
            points.append(MealSparkPoint(minute: minute, value: value))
        }
        return points
    }
}
