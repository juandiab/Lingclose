import Foundation

/// Composición corporal de Apple Salud para el análisis (T-33, adenda 1): el valor más reciente de cada medida
/// **dentro del período o anterior** y, para peso, grasa y masa magra, la tendencia del período. Solo contexto.
struct BodyComposition: Sendable, Hashable {
    /// Un valor por medida, con un decimal; las que no tienen muestra no están.
    var latest: [BodyMetric: Double] = [:]
    var trends: [BodyTrend] = []

    static let empty = BodyComposition()

    /// Separación mínima entre la primera y la última muestra para dar tendencia.
    static let minimumTrendSpan: TimeInterval = 3 * 86_400

    var isEmpty: Bool { latest.isEmpty && trends.isEmpty }

    /// Puro: `latest` es la muestra más reciente de cada medida hasta el final del período; `inPeriod`, las muestras de
    /// las medidas con tendencia dentro del período. Hay tendencia con ≥ 2 muestras separadas ≥ 3 días.
    static func make(latest: [BodyMetric: BodyMeasurement], inPeriod: [BodyMetric: [BodyMeasurement]],
                     timeZone: TimeZone) -> BodyComposition {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var result = BodyComposition()
        for (metric, measurement) in latest where measurement.value.isFinite {
            result.latest[metric] = r1(measurement.value)
        }
        for metric in BodyMetric.trended {
            let samples = (inPeriod[metric] ?? []).filter { $0.value.isFinite }.sorted { $0.date < $1.date }
            guard samples.count >= 2, let first = samples.first, let last = samples.last,
                  last.date.timeIntervalSince(first.date) >= minimumTrendSpan else { continue }
            result.trends.append(BodyTrend(
                metric: metric.rawValue,
                first: BodyTrendPoint(day: SleepNightGrouper.dayString(first.date, calendar: calendar), value: r1(first.value)),
                last: BodyTrendPoint(day: SleepNightGrouper.dayString(last.date, calendar: calendar), value: r1(last.value))))
        }
        return result
    }

    private static func r1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}
