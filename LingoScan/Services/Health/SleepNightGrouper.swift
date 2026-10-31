import Foundation
import LingoCore

/// Agrupa tramos de sueño de Apple Salud en noches (T-33). Puro: sin `HKHealthStore`, probado con tramos sintéticos.
///
/// 1. Cada tramo va a la noche de su inicio con la convención de `NightReport`: la fecha local del día en que empieza;
///    si empieza antes de las 12:00 locales, cuenta para el día anterior.
/// 2. Dentro de una noche, por origen, los tramos se juntan en sesiones (un hueco de más de 3 h abre otra) y se toma
///    la sesión con más tiempo dormido; así una siesta no se suma a la noche.
/// 3. Con varios orígenes (Watch e iPhone) se usa **uno solo**, para no contar dos veces: el que distingue etapas y,
///    a igualdad, el que tiene más tiempo dormido.
/// 4. Minutos por unión de intervalos (los solapes de un mismo origen no se cuentan dos veces).
enum SleepNightGrouper {
    static let sessionGap: TimeInterval = 3 * 3_600
    /// Las sesiones que empiezan antes de esta hora local cuentan para el día anterior.
    static let nightCutoffHour = 12

    static func nights(from segments: [SleepSegment], timeZone: TimeZone) -> [SleepNight] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let valid = segments.filter { $0.end > $0.start }
        let byNight = Dictionary(grouping: valid) { nightKey(for: $0.start, calendar: calendar) }
        return byNight.compactMap { key, segments in night(key, segments) }.sorted { $0.night < $1.night }
    }

    /// Fecha local (`YYYY-MM-DD`) de la noche a la que pertenece un instante.
    static func nightKey(for date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let day = hour < nightCutoffHour ? (calendar.date(byAdding: .day, value: -1, to: date) ?? date) : date
        return dayString(day, calendar: calendar)
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Interno

    private static func night(_ key: String, _ segments: [SleepSegment]) -> SleepNight? {
        let candidates = Dictionary(grouping: segments, by: \.source).map { source, segments in
            (source: source, session: mainSession(segments))
        }
        guard let chosen = candidates.max(by: { a, b in
            let aStages = a.session.contains { $0.stage.isStage }, bStages = b.session.contains { $0.stage.isStage }
            if aStages != bStages { return !aStages }
            let aAsleep = minutes(a.session, where: \.stage.isAsleep), bAsleep = minutes(b.session, where: \.stage.isAsleep)
            if aAsleep != bAsleep { return aAsleep < bAsleep }
            return a.source > b.source
        }), let bed = chosen.session.map(\.start).min(), let wake = chosen.session.map(\.end).max(), wake > bed else {
            return nil
        }
        let session = chosen.session
        let hasStages = session.contains { $0.stage.isStage }
        return SleepNight(
            night: key, bedAt: UTCInstant(bed), wakeAt: UTCInstant(wake),
            inBedMin: Int((wake.timeIntervalSince(bed) / 60).rounded()),
            asleepMin: minutes(session, where: \.stage.isAsleep),
            awakeMin: minutes(session) { $0.stage == .awake },
            deepMin: hasStages ? minutes(session) { $0.stage == .deep } : nil,
            remMin: hasStages ? minutes(session) { $0.stage == .rem } : nil,
            coreMin: hasStages ? minutes(session) { $0.stage == .core } : nil,
            awakenings: awakenings(session))
    }

    /// Sesión (tramos separados por menos de `sessionGap`) con más tiempo dormido; a igualdad, la más larga.
    private static func mainSession(_ segments: [SleepSegment]) -> [SleepSegment] {
        var sessions: [[SleepSegment]] = []
        var currentEnd = Date.distantPast
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if sessions.isEmpty || segment.start.timeIntervalSince(currentEnd) > sessionGap {
                sessions.append([segment])
                currentEnd = segment.end
            } else {
                sessions[sessions.count - 1].append(segment)
                currentEnd = max(currentEnd, segment.end)
            }
        }
        return sessions.max { a, b in
            let aAsleep = minutes(a, where: \.stage.isAsleep), bAsleep = minutes(b, where: \.stage.isAsleep)
            if aAsleep != bAsleep { return aAsleep < bAsleep }
            return span(a) < span(b)
        } ?? []
    }

    private static func span(_ segments: [SleepSegment]) -> TimeInterval {
        guard let start = segments.map(\.start).min(), let end = segments.map(\.end).max() else { return 0 }
        return end.timeIntervalSince(start)
    }

    private static func minutes(_ segments: [SleepSegment], where include: (SleepSegment) -> Bool) -> Int {
        let total = union(segments.filter(include)).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        return Int((total / 60).rounded())
    }

    /// Unión de intervalos ordenada, sin solapes.
    private static func union(_ segments: [SleepSegment]) -> [(start: Date, end: Date)] {
        var merged: [(start: Date, end: Date)] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, segment.start <= last.end {
                merged[merged.count - 1].end = max(last.end, segment.end)
            } else {
                merged.append((segment.start, segment.end))
            }
        }
        return merged
    }

    /// Tramos despierto (ya unidos) que tienen sueño antes y después.
    private static func awakenings(_ session: [SleepSegment]) -> Int {
        let asleep = union(session.filter(\.stage.isAsleep))
        guard let firstAsleep = asleep.first?.start, let lastAsleep = asleep.last?.end else { return 0 }
        return union(session.filter { $0.stage == .awake })
            .filter { $0.start >= firstAsleep && $0.end <= lastAsleep }
            .count
    }
}
