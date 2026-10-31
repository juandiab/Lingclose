import Foundation

/// Conversión rápida UTC → hora local de una zona, precalculando sus cambios de horario en un intervalo.
/// Evita llamar a `Calendar` por lectura (90 días × 1 440 lecturas).
struct LocalClock: Sendable {
    let timeZone: TimeZone
    /// Instantes UTC (segundos) en los que cambia el desfase, ascendentes.
    private let transitions: [Int64]
    /// `offsets[i]` rige antes de `transitions[i]`; el último rige después de la última transición.
    private let offsets: [Int64]

    init(timeZone: TimeZone, from: Int64, to: Int64) {
        self.timeZone = timeZone
        var transitions: [Int64] = []
        var offsets: [Int64] = [Int64(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(from))))]
        var cursor = Date(timeIntervalSince1970: TimeInterval(from))
        while let next = timeZone.nextDaylightSavingTimeTransition(after: cursor),
              next.timeIntervalSince1970 <= TimeInterval(to), next > cursor {
            transitions.append(Int64(next.timeIntervalSince1970.rounded()))
            offsets.append(Int64(timeZone.secondsFromGMT(for: next)))
            cursor = next
        }
        self.transitions = transitions
        self.offsets = offsets
    }

    func offset(at utc: Int64) -> Int64 {
        var index = 0
        while index < transitions.count, utc >= transitions[index] { index += 1 }
        return offsets[index]
    }

    /// Segundos "de reloj local" desde 1970-01-01 00:00 local.
    func localSeconds(_ utc: Int64) -> Int64 { utc + offset(at: utc) }

    /// Número de día local (días desde 1970-01-01 local).
    static func dayNumber(localSeconds: Int64) -> Int64 { floorDiv(localSeconds, 86_400) }

    /// Minuto de reloj local desde la medianoche (0…1439).
    static func minuteOfDay(localSeconds: Int64) -> Int {
        Int((localSeconds - floorDiv(localSeconds, 86_400) * 86_400) / 60)
    }

    func dayNumber(_ utc: Int64) -> Int64 { Self.dayNumber(localSeconds: localSeconds(utc)) }

    func minuteOfDay(_ utc: Int64) -> Int { Self.minuteOfDay(localSeconds: localSeconds(utc)) }

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 { a >= 0 ? a / b : (a - b + 1) / b }
}
