import Foundation
import LingoCore

/// Textos de los insights de Hoy (T-23): respuesta a comida, efecto del ejercicio y episodios rápidos.
/// Informativos, no médicos.
enum InsightFormat {
    static func minutes(_ seconds: Int64) -> Int { Int((Double(seconds) / 60).rounded()) }

    /// Subida mostrada: nunca negativa (si la glucosa bajó tras comer, "+0").
    static func rise(_ response: MealResponse) -> Int { max(0, Int(response.rise.rounded())) }

    /// "Subió +42 mg/dL, pico a los 50 min, volvió a los 120 min" (o "sin volver en 3 h").
    static func mealSummary(_ response: MealResponse) -> String {
        let rise = rise(response)
        let peak = minutes(response.timeToPeak)
        if let back = response.timeToReturn {
            return String(localized: "today.insight.meal.summary", defaultValue: "Subió +\(rise) mg/dL, pico a los \(peak) min, volvió a los \(minutes(back)) min")
        }
        return String(localized: "today.insight.meal.noReturn", defaultValue: "Subió +\(rise) mg/dL, pico a los \(peak) min, sin volver en 3 h")
    }

    /// Sin respuesta ni efecto: "todavía" si la marca es de las últimas 3 h.
    static func notEnoughData(since date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < Double(MealResponse.horizon)
            ? String(localized: "today.insight.meal.pending", defaultValue: "Sin datos suficientes todavía")
            : String(localized: "today.insight.meal.unavailable", defaultValue: "Sin datos suficientes")
    }

    /// "Bajó 25 mg/dL en 60 min", "Subió 8 mg/dL en 60 min" o "Sin cambio en 60 min"; `nil` sin lectura a los 60 min.
    static func exerciseSummary(_ effect: ExerciseEffect) -> String? {
        guard let delta = effect.deltaAt60.map({ Int($0.rounded()) }) else { return nil }
        if delta < 0 {
            return String(localized: "today.insight.exercise.drop", defaultValue: "Bajó \(-delta) mg/dL en 60 min")
        }
        if delta > 0 {
            return String(localized: "today.insight.exercise.rise", defaultValue: "Subió \(delta) mg/dL en 60 min")
        }
        return String(localized: "today.insight.exercise.flat", defaultValue: "Sin cambio en 60 min")
    }

    /// "100 → 150 mg/dL".
    static func rateRange(_ event: RateEvent) -> String {
        String(localized: "today.insight.rate.range", defaultValue: "\(event.from) → \(event.to) mg/dL")
    }

    /// "+2,5 mg/dL/min".
    static func rateSlope(_ event: RateEvent) -> String {
        let value = event.slopePerMinute.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
        return String(localized: "today.insight.rate.slope", defaultValue: "\(value) mg/dL/min")
    }
}
