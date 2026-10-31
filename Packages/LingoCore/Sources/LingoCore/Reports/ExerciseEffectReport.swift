/// Reporte 6 — efecto del ejercicio (T-27a). Informativo, no médico.
///
/// Por cada ejercicio del período, `ExerciseEffect` (línea base = media de los 15 min previos; fin = inicio +
/// duración, o + 30 min sin duración) y además:
/// - `deltaAtEnd`: lectura más cercana al fin (±5 min) − línea base ("durante").
/// - `deltaAt60` (de `ExerciseEffect`) y `deltaAt120`: lectura a fin + 60 / + 120 min (±5 min) − línea base.
/// - `dropToMinimum`: mínimo entre el inicio y fin + 90 min − línea base.
/// `effect == nil` sin lecturas previas o sin lecturas desde el inicio.
/// Mínimo: un agregado (global o por `DurationBucket`) necesita ≥ `ReportThresholds.minimumEventsPerGroup` (3)
/// ejercicios con efecto; cada media usa solo los valores no nulos y es `nil` si no hay ninguno.
public struct ExerciseEffectReport: Sendable, Hashable, Codable {
    public struct Effect: Sendable, Hashable, Codable {
        public let baseline: Double
        public let minimum: Int
        public let minutesToMinimum: Int
        public let dropToMinimum: Double
        public let deltaAtEnd: Double?
        public let deltaAt60: Double?
        public let deltaAt120: Double?

        enum CodingKeys: String, CodingKey {
            case baseline
            case minimum = "min"
            case minutesToMinimum = "min_at_minute"
            case dropToMinimum = "drop_to_min"
            case deltaAtEnd = "delta_at_end"
            case deltaAt60 = "delta_at_60"
            case deltaAt120 = "delta_at_120"
        }
    }

    public struct Session: Sendable, Hashable, Codable {
        public let at: UTCInstant
        public let localMinute: Int
        public let slot: TimeOfDaySlot
        /// Duración marcada; `nil` si la marca no la tiene (se asumen 30 min para el cálculo).
        public let durationMinutes: Int?
        public let durationBucket: DurationBucket
        public let effect: Effect?

        enum CodingKeys: String, CodingKey {
            case at
            case localMinute = "local_minute"
            case slot
            case durationMinutes = "duration_min"
            case durationBucket = "duration_bucket"
            case effect
        }
    }

    public struct Stats: Sendable, Hashable, Codable {
        public let sessions: Int
        public let analyzed: Int
        public let meanDeltaAtEnd: Double?
        public let meanDeltaAt60: Double?
        public let meanDeltaAt120: Double?
        public let meanDropToMinimum: Double?

        public var isReliable: Bool { analyzed >= ReportThresholds.minimumEventsPerGroup }

        init(_ sessions: [Session]) {
            let effects = sessions.compactMap(\.effect)
            self.sessions = sessions.count
            analyzed = effects.count
            let reliable = effects.count >= ReportThresholds.minimumEventsPerGroup
            func mean(_ values: [Double]) -> Double? { reliable ? ReportRounding.r1(optional: ReportRounding.mean(values)) : nil }
            meanDeltaAtEnd = mean(effects.compactMap(\.deltaAtEnd))
            meanDeltaAt60 = mean(effects.compactMap(\.deltaAt60))
            meanDeltaAt120 = mean(effects.compactMap(\.deltaAt120))
            meanDropToMinimum = mean(effects.map(\.dropToMinimum))
        }

        enum CodingKeys: String, CodingKey {
            case sessions, analyzed
            case meanDeltaAtEnd = "mean_delta_at_end"
            case meanDeltaAt60 = "mean_delta_at_60"
            case meanDeltaAt120 = "mean_delta_at_120"
            case meanDropToMinimum = "mean_drop_to_min"
        }
    }

    public internal(set) var sessions: [Session]
    public let overall: Stats
    public let byDuration: [ReportGroup<DurationBucket, Stats>]

    public var hasEnoughData: Bool { overall.analyzed > 0 }

    enum CodingKeys: String, CodingKey {
        case sessions, overall
        case byDuration = "by_duration"
    }

    init(context: ReportContext) {
        var result: [Session] = []
        for event in context.exercises {
            let start = event.at.epochSeconds
            let duration = event.durationMin.map { Int64(max(0, $0)) * 60 } ?? ExerciseEffect.defaultDuration
            let end = start + duration
            let window = context.range(from: start - ExerciseEffect.beforeWindow,
                                       to: end + 7_200 + ReportThresholds.pointToleranceSeconds + 1)
            let effect = ExerciseEffect(start: event.at, end: UTCInstant(epochSeconds: end), samples: context.samples(window))
                .map { e -> Effect in
                    func delta(_ target: Int64) -> Double? {
                        context.value(near: target).map { ReportRounding.r1(Double($0) - e.before) }
                    }
                    return Effect(
                        baseline: ReportRounding.r1(e.before), minimum: e.minAfter,
                        minutesToMinimum: Int((e.minAt.epochSeconds - start) / 60),
                        dropToMinimum: ReportRounding.r1(Double(e.minAfter) - e.before),
                        deltaAtEnd: delta(end), deltaAt60: ReportRounding.r1(optional: e.deltaAt60), deltaAt120: delta(end + 7_200))
                }
            let minute = context.clock.minuteOfDay(start)
            result.append(Session(at: event.at, localMinute: minute, slot: TimeOfDaySlot(minuteOfDay: minute),
                                  durationMinutes: event.durationMin, durationBucket: DurationBucket(durationMinutes: event.durationMin),
                                  effect: effect))
        }
        sessions = result
        overall = Stats(result)
        byDuration = DurationBucket.allCases.map { bucket in
            ReportGroup(key: bucket, stats: Stats(result.filter { $0.durationBucket == bucket }))
        }
    }
}
