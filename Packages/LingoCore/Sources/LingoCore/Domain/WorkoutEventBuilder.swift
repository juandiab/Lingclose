/// Convierte un `WorkoutSummary` en evento `exercise` del diario (T-21 §5). Puro: ids, reloj y zona inyectados.
public enum WorkoutEventBuilder {
    /// Duración admitida por el diario (igual que el editor manual).
    public static let durationRange = 1...1_440

    /// Alta: `at` = inicio, duración, texto resumen, `synthetic = false`, `parent_edit_id` nulo.
    public static func event(
        from workout: WorkoutSummary, eventID: String, editID: String, tz: String, appID: String, now: UTCInstant
    ) -> DiaryEvent {
        DiaryEvent(
            eventID: eventID, kind: .exercise, at: workout.start, tz: tz,
            durationMin: clampedDuration(workout.durationMin), text: text(for: workout),
            createdAt: now, updatedAt: now, revision: 1, editID: editID, parentEditID: nil,
            editedByAppID: appID, deleted: false, synthetic: false)
    }

    /// Edición nueva con linaje si el entrenamiento cambió (`at`, duración o texto); `nil` si no cambió o si el
    /// usuario borró el evento (no se resucita).
    public static func update(
        existing: DiaryEvent, with workout: WorkoutSummary, editID: String, appID: String, now: UTCInstant
    ) -> DiaryEvent? {
        guard !existing.deleted else { return nil }
        let duration = clampedDuration(workout.durationMin)
        let summary = text(for: workout)
        guard existing.at != workout.start || existing.durationMin != duration || existing.text != summary
                || existing.kind != .exercise
        else { return nil }
        var next = existing
        next.kind = .exercise
        next.at = workout.start
        next.durationMin = duration
        next.carbsG = nil
        next.text = summary
        next.updatedAt = now
        next.revision = existing.revision + 1
        next.parentEditID = existing.editID
        next.editID = editID
        next.editedByAppID = appID
        next.importedFrom = nil
        return next
    }

    /// "Correr · 5,2 km · 320 kcal · FC media 142", solo con lo que exista.
    public static func text(for workout: WorkoutSummary) -> String {
        var parts = [workout.activityName]
        if let m = workout.distanceMeters, m.isFinite, m > 0 {
            parts.append(m >= 1_000 ? decimal(m / 1_000) + " km" : String(Int(m.rounded())) + " m")
        }
        if let kcal = workout.activeEnergyKcal, kcal.isFinite, kcal >= 0.5 {
            parts.append(String(Int(kcal.rounded())) + " kcal")
        }
        if let hr = workout.averageHeartRate, hr.isFinite, hr > 0 {
            parts.append("FC media " + String(Int(hr.rounded())))
        }
        return parts.joined(separator: " · ")
    }

    private static func clampedDuration(_ minutes: Int) -> Int {
        min(max(minutes, durationRange.lowerBound), durationRange.upperBound)
    }

    /// Un decimal con coma (es): 5,2.
    private static func decimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return String(tenths / 10) + "," + String(tenths % 10)
    }
}
