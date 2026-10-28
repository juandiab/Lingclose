import LingoCore

/// La última comida y el último ejercicio del diario antes de una alerta (T-25). Solo lo que necesitan las reglas
/// y el asistente: horas, nutrientes agregados, tipo de actividad (solo de entrenamientos de Salud) y duración.
/// Nunca el texto libre de la comida ni de una nota.
struct CoachingActivity: Sendable, Equatable {
    var lastMealAt: UTCInstant?
    /// Nutrientes efectivos de la comida (`meal_nutrition`) o, sin registro, solo sus carbohidratos.
    var lastMealNutrients: Nutrients?
    /// Fin del último ejercicio (`at + duración`).
    var lastExerciseEnd: UTCInstant?
    /// Tipo de actividad ("Correr") solo si el evento viene de un entrenamiento de Salud; el texto manual no sale.
    var lastExerciseKind: String?
    var lastExerciseDurationMin: Int?

    static let none = CoachingActivity()

    /// Toma la última comida y el último ejercicio (por su fin) de `events`, ignorando lo posterior a `now`.
    static func from(
        _ events: [DiaryEvent], now: UTCInstant,
        nutrients: (DiaryEvent) -> Nutrients?, workoutKind: (DiaryEvent) -> String?
    ) -> CoachingActivity {
        let past = events.filter { !$0.deleted && $0.at <= now }
        var activity = CoachingActivity()
        if let meal = past.filter({ $0.kind == .meal }).max(by: { $0.at < $1.at }) {
            activity.lastMealAt = meal.at
            activity.lastMealNutrients = nutrients(meal) ?? meal.carbsG.map { Nutrients(carbsG: $0) }
        }
        func end(_ e: DiaryEvent) -> UTCInstant { e.at.adding(seconds: Int64(e.durationMin ?? 0) * 60) }
        if let exercise = past.filter({ $0.kind == .exercise }).max(by: { end($0) < end($1) }) {
            activity.lastExerciseEnd = min(end(exercise), now)
            activity.lastExerciseKind = workoutKind(exercise)
            activity.lastExerciseDurationMin = exercise.durationMin
        }
        return activity
    }
}
