import Foundation

/// Enlaces entrenamiento de Salud → evento `exercise` (T-21 §5, tabla `workout_links` de la migración v3).
/// Tabla local: no se exporta al `.lingoscan`.
extension SQLiteStore {
    /// Evento creado para ese `HKWorkout.uuid`, o `nil` si no se ha importado.
    public func eventID(forWorkoutUUID uuid: String) throws -> String? {
        try connection.queryFirst("SELECT event_id FROM workout_links WHERE health_workout_uuid = ?",
                                  [SQLiteValue(uuid)]) { $0.text(0) } ?? nil
    }

    /// `true` si el evento se creó a partir de un entrenamiento de Salud (su texto empieza por el tipo de actividad).
    public func isWorkoutEvent(eventID: String) throws -> Bool {
        try connection.queryFirst("SELECT 1 FROM workout_links WHERE event_id = ? LIMIT 1",
                                  [SQLiteValue(eventID)]) { $0.int(0) } != nil
    }

    /// Enlaza un entrenamiento con un evento existente. Idempotente: si el uuid ya estaba enlazado no cambia nada.
    public func linkWorkout(uuid: String, eventID: String, at: UTCInstant) throws {
        try connection.transaction { try insertLink(uuid: uuid, eventID: eventID, at: at) }
    }

    /// Guarda el evento y su enlace en **una** transacción. Si el uuid ya tenía evento, no crea otro y devuelve
    /// el `event_id` ya enlazado; si no, devuelve el del evento nuevo.
    @discardableResult
    public func saveWorkoutEvent(_ event: DiaryEvent, workoutUUID: String) throws -> String {
        try connection.transaction {
            if let linked = try eventID(forWorkoutUUID: workoutUUID) { return linked }
            try upsertEvent(event)
            try insertLink(uuid: workoutUUID, eventID: event.eventID, at: event.updatedAt)
            return event.eventID
        }
    }

    /// Número de entrenamientos importados (para Ajustes).
    public func linkedWorkoutCount() throws -> Int {
        try connection.queryFirst("SELECT COUNT(*) FROM workout_links") { $0.int(0) ?? 0 } ?? 0
    }

    private func insertLink(uuid: String, eventID: String, at: UTCInstant) throws {
        try connection.run(
            "INSERT OR IGNORE INTO workout_links (health_workout_uuid, event_id, imported_at_epoch_s) VALUES (?, ?, ?)",
            [SQLiteValue(uuid), SQLiteValue(eventID), SQLiteValue(at.epochSeconds)])
    }
}
