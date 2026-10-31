import LingoCore

/// Una noche de sueño de Apple Salud (T-33). `night` es la fecha local `YYYY-MM-DD` del día en que empieza, con la
/// convención de `NightReport`: una sesión que empieza antes de las 12:00 locales cuenta para el día anterior.
/// Las etapas son `nil` si el origen no las distingue (solo "dormido").
struct SleepNight: Sendable, Hashable, Codable {
    var night: String
    var bedAt: UTCInstant
    var wakeAt: UTCInstant
    var inBedMin: Int
    var asleepMin: Int
    var awakeMin: Int
    var deepMin: Int?
    var remMin: Int?
    var coreMin: Int?
    /// Tramos despierto entre dos tramos dormido.
    var awakenings: Int

    enum CodingKeys: String, CodingKey {
        case night
        case bedAt = "bed_at"
        case wakeAt = "wake_at"
        case inBedMin = "in_bed_min"
        case asleepMin = "asleep_min"
        case awakeMin = "awake_min"
        case deepMin = "deep_min"
        case remMin = "rem_min"
        case coreMin = "core_min"
        case awakenings
    }
}
