import Foundation
import LingoCore

/// Lo único que sale del teléfono al preguntar al asistente tras una alerta (T-25): tipo de alerta, valor y
/// pendiente, hora local, tiempo en rango del día, minutos desde la última comida y sus nutrientes, minutos desde el
/// último ejercicio y su tipo/duración, y los consejos de reglas ya mostrados (para que no los repita). Nunca
/// lecturas crudas, nombres de comidas, notas, fotos, fechas ni identificadores. `locale` solo elige el idioma.
struct CoachingRequest: Sendable, Equatable {
    var kind: AlertKind
    var valueMgdl: Int?
    var slopePerMinute: Double?
    var localHour: Int
    var timeInRangeToday: Double?
    var minutesSinceLastMeal: Int?
    var meal: Nutrients?
    var minutesSinceLastExercise: Int?
    /// Tipo de actividad de un entrenamiento de Salud ("Correr"); nunca texto libre.
    var exerciseKind: String?
    var exerciseDurationMin: Int?
    /// Textos de los consejos de reglas ya mostrados.
    var shownTips: [String]
    var locale: String

    init(record: CoachingRecord, locale: String) {
        let c = record.context
        kind = c.kind
        valueMgdl = c.value
        slopePerMinute = c.slopePerMinute
        localHour = c.hour
        timeInRangeToday = c.timeInRangeToday
        minutesSinceLastMeal = c.minutesSinceLastMeal
        meal = c.minutesSinceLastMeal == nil ? nil : record.mealNutrients
        minutesSinceLastExercise = c.minutesSinceLastExercise
        exerciseKind = c.minutesSinceLastExercise == nil ? nil : record.exerciseKind
        exerciseDurationMin = c.minutesSinceLastExercise == nil ? nil : record.exerciseDurationMin
        shownTips = record.tips.map { "\($0.localizedTitle): \($0.localizedBody)" }
        self.locale = locale
    }

    /// Mensaje del usuario: los agregados como JSON (claves ordenadas, `null` lo que falta).
    var userText: String {
        func rounded(_ value: Double?, _ decimals: Double = 1) -> Any {
            value.map { ($0 * pow(10, decimals)).rounded() / pow(10, decimals) } ?? NSNull()
        }
        func optional(_ value: Any?) -> Any { value ?? NSNull() }
        let mealObject: Any = minutesSinceLastMeal.map { minutes -> [String: Any] in
            [
                "minutes_ago": minutes,
                "kcal": rounded(meal?.kcal, 0),
                "carbs_g": rounded(meal?.carbsG),
                "protein_g": rounded(meal?.proteinG),
                "fat_g": rounded(meal?.fatG),
            ]
        } ?? NSNull()
        let exerciseObject: Any = minutesSinceLastExercise.map { minutes -> [String: Any] in
            ["minutes_since_end": minutes, "kind": optional(exerciseKind), "duration_min": optional(exerciseDurationMin)]
        } ?? NSNull()
        let object: [String: Any] = [
            "alert": [
                "kind": kind.rawValue,
                "value_mgdl": optional(valueMgdl),
                "slope_mgdl_per_min": rounded(slopePerMinute),
            ] as [String: Any],
            "local_hour": localHour,
            "time_in_range_today_pct": timeInRangeToday.map { Int(($0 * 100).rounded()) } ?? NSNull(),
            "last_meal": mealObject,
            "last_exercise": exerciseObject,
            "tips_already_shown": shownTips,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return "Contexto agregado de la alerta (no hay lecturas individuales):\n" + (String(data: data, encoding: .utf8) ?? "{}")
    }
}
