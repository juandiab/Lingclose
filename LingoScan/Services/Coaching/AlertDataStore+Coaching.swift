import LingoCore

extension AlertDataStore {
    /// Por defecto no hay diario (dobles de prueba de T-24): los consejos se eligen sin comida ni ejercicio.
    func coachingActivity(in range: ClosedRange<UTCInstant>) async -> CoachingActivity { .none }
}

extension SQLiteStore {
    /// Última comida y último ejercicio del rango (T-25). Un fallo de lectura no impide avisar: devuelve `.none`.
    func coachingActivity(in range: ClosedRange<UTCInstant>) async -> CoachingActivity {
        guard let events = try? events(in: range) else { return .none }
        var nutrients: [String: Nutrients] = [:]
        var kinds: [String: String] = [:]
        for event in events where event.kind == .meal {
            if let record = try? mealNutrition(eventID: event.eventID) { nutrients[event.eventID] = record.effectiveNutrients }
        }
        for event in events where event.kind == .exercise {
            if (try? isWorkoutEvent(eventID: event.eventID)) == true, let text = event.text {
                // Texto de `WorkoutEventBuilder`: "Correr · 5,2 km · …"; solo el tipo de actividad.
                kinds[event.eventID] = text.components(separatedBy: " · ").first
            }
        }
        return CoachingActivity.from(events, now: range.upperBound,
                                     nutrients: { nutrients[$0.eventID] }, workoutKind: { kinds[$0.eventID] })
    }
}
