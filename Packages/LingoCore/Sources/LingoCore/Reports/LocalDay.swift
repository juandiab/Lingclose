import Foundation

/// Día local de calendario de un reporte. `start`/`end` son sus medianoches en UTC (`end` exclusivo); un día de
/// cambio de horario dura 23 o 25 h.
public struct LocalDay: Sendable, Hashable, Codable, Comparable {
    /// `YYYY-MM-DD` en la zona del período.
    public let date: String
    public let start: UTCInstant
    public let end: UTCInstant
    /// Día ISO de la semana: 1 = lunes … 7 = domingo.
    public let weekday: Int

    public init(date: String, start: UTCInstant, end: UTCInstant, weekday: Int) {
        self.date = date
        self.start = start
        self.end = end
        self.weekday = weekday
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool { lhs.start < rhs.start }

    public var durationSeconds: Int64 { end.epochSeconds - start.epochSeconds }

    /// Día local número `number` (días desde 1970-01-01 local).
    static func make(number: Int64, calendar: Calendar, clock: LocalClock) -> LocalDay {
        // Mediodía local aproximado → UTC, y de ahí la medianoche real con `Calendar` (cubre cambios a las 00:00).
        let noonLocal = number * 86_400 + 43_200
        var utc = noonLocal - clock.offset(at: noonLocal)
        utc = noonLocal - clock.offset(at: utc)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(utc)))
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let date = String(UTCInstant(epochSeconds: number * 86_400).rfc3339.prefix(10))
        let weekday = Int((number % 7 + 7 + 3) % 7) + 1
        return LocalDay(date: date, start: UTCInstant(start), end: UTCInstant(end), weekday: weekday)
    }
}
