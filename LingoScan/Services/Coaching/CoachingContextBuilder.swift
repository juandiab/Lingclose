import Foundation
import LingoCore

/// Arma el `CoachingContext` de una alerta (T-25) a partir del evento, la actividad del diario y las lecturas del
/// día. Puro: sin reloj ni E/S.
enum CoachingContextBuilder {
    /// Por debajo de estas lecturas en el día no se calcula el tiempo en rango.
    static let minimumSamplesForTimeInRange = 30

    static func context(
        for event: AlertEvent, activity: CoachingActivity, daySamples: [BasicStats.Sample],
        low: Int, high: Int, timeZone: TimeZone
    ) -> CoachingContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func minutes(since instant: UTCInstant?) -> Int? {
            instant.map { max(0, Int((event.at.epochSeconds - $0.epochSeconds) / 60)) }
        }
        return CoachingContext(
            kind: event.kind,
            value: event.value,
            slopePerMinute: event.slopePerMinute,
            minutesSinceLastMeal: minutes(since: activity.lastMealAt),
            lastMealCarbsG: activity.lastMealNutrients?.carbsG,
            minutesSinceLastExercise: minutes(since: activity.lastExerciseEnd),
            hour: calendar.component(.hour, from: event.at.date),
            timeInRangeToday: timeInRange(daySamples, low: low, high: high))
    }

    /// Fracción de lecturas del día entre las líneas del rango de referencia (incluidas).
    static func timeInRange(_ samples: [BasicStats.Sample], low: Int, high: Int) -> Double? {
        guard samples.count >= minimumSamplesForTimeInRange, low <= high else { return nil }
        return BasicStats(samples: samples, range: low...high).timeInRange
    }

    /// Inicio del día local de `instant`, pero nunca menos de 6 h antes (una comida a las 23:30 sigue contando a la 1:00).
    static func activityWindowStart(for instant: UTCInstant, timeZone: TimeZone) -> UTCInstant {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let midnight = UTCInstant(calendar.startOfDay(for: instant.date))
        return min(midnight, instant.adding(seconds: -6 * 3600))
    }

    static func startOfDay(for instant: UTCInstant, timeZone: TimeZone) -> UTCInstant {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return UTCInstant(calendar.startOfDay(for: instant.date))
    }
}
