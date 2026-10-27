/// Entrenamiento leído de Apple Salud (T-21 §5), ya traducido a tipos puros. Solo lectura: LingoScan nunca escribe
/// ejercicio en Salud.
public struct WorkoutSummary: Sendable, Hashable {
    /// `HKWorkout.uuid` en minúsculas; clave de `workout_links`.
    public var uuid: String
    /// Tipo de actividad ya legible (p. ej. "Correr").
    public var activityName: String
    public var start: UTCInstant
    public var end: UTCInstant
    public var durationMin: Int
    public var activeEnergyKcal: Double?
    public var distanceMeters: Double?
    public var averageHeartRate: Double?
    public var sourceName: String?

    public init(
        uuid: String, activityName: String, start: UTCInstant, end: UTCInstant, durationMin: Int,
        activeEnergyKcal: Double? = nil, distanceMeters: Double? = nil, averageHeartRate: Double? = nil,
        sourceName: String? = nil
    ) {
        self.uuid = uuid
        self.activityName = activityName
        self.start = start
        self.end = end
        self.durationMin = durationMin
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.sourceName = sourceName
    }
}
