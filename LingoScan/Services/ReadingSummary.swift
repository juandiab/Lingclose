import LingoCore

/// Última lectura vista por el coordinador, para la UI.
struct ReadingSummary: Sendable, Equatable {
    let lifeCount: Int
    let measuredAt: UTCInstant
    let valueMgdl: Int?
    let eligible: Bool
    let exclusion: ExclusionReason?
    let trend: Int?
    let origin: ReadingOrigin

    init(_ reading: GlucoseReading) {
        lifeCount = reading.lifeCount
        measuredAt = reading.measuredAt
        valueMgdl = reading.value
        eligible = reading.eligibility.isEligible
        exclusion = reading.eligibility.reason
        trend = reading.raw.trend
        origin = reading.origin
    }
}
