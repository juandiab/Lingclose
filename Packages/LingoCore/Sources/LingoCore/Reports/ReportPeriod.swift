import Foundation

/// Período de un reporte: `[start, end)` en UTC, interpretado en días locales de `timeZoneIdentifier`.
///
/// Los presets (7/14/30/90 días) empiezan a la medianoche local de hace `n − 1` días y terminan en `now`
/// (el día de hoy cuenta aunque esté a medias). El rango libre va de la medianoche del primer día a la del día
/// siguiente al último, recortado a `now` si se da. Todas las horas locales de los reportes usan esta zona, no
/// `tz_at_capture` de cada lectura.
public struct ReportPeriod: Sendable, Hashable, Codable {
    public enum Preset: Int, Sendable, Hashable, Codable, CaseIterable {
        case days7 = 7
        case days14 = 14
        case days30 = 30
        case days90 = 90

        public var days: Int { rawValue }
    }

    public let start: UTCInstant
    /// Exclusivo. Nunca anterior a `start`.
    public let end: UTCInstant
    public let timeZoneIdentifier: String

    public init(start: UTCInstant, end: UTCInstant, timeZone: TimeZone) {
        self.start = start
        self.end = max(start, end)
        timeZoneIdentifier = timeZone.identifier
    }

    /// Últimos `days` días locales (incluido el de `now`), hasta `now`.
    public static func last(_ days: Int, endingAt now: UTCInstant, timeZone: TimeZone) -> ReportPeriod {
        let calendar = Self.calendar(timeZone)
        let today = calendar.startOfDay(for: now.date)
        let first = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
        return ReportPeriod(start: UTCInstant(first), end: now, timeZone: timeZone)
    }

    public static func preset(_ preset: Preset, endingAt now: UTCInstant, timeZone: TimeZone) -> ReportPeriod {
        last(preset.days, endingAt: now, timeZone: timeZone)
    }

    /// Rango libre de días locales completos, de `first` a `last` (ambos incluidos; el orden da igual).
    public static func days(from first: Date, through last: Date, timeZone: TimeZone, now: UTCInstant? = nil) -> ReportPeriod {
        let calendar = Self.calendar(timeZone)
        let a = calendar.startOfDay(for: min(first, last))
        let b = calendar.startOfDay(for: max(first, last))
        let after = calendar.date(byAdding: .day, value: 1, to: b) ?? b
        var end = UTCInstant(after)
        if let now { end = min(end, now) }
        return ReportPeriod(start: UTCInstant(a), end: end, timeZone: timeZone)
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0) ?? .current }

    public var durationSeconds: Int64 { end.epochSeconds - start.epochSeconds }

    public func contains(_ instant: UTCInstant) -> Bool { instant >= start && instant < end }

    /// Desde dónde hay que leer lecturas y eventos para `ReportBuilder.build`: lo anterior entre `start` y el
    /// comienzo de las dos semanas locales que compara `WeeklyComparisonReport`, menos 30 min de líneas base.
    public var dataStart: UTCInstant {
        let calendar = Self.calendar(timeZone)
        let lastDay = calendar.startOfDay(for: max(start, end.adding(seconds: -1)).date)
        let previousWeek = calendar.date(byAdding: .day, value: -13, to: lastDay) ?? lastDay
        return min(start, UTCInstant(previousWeek)).adding(seconds: -2 * MealResponse.baselineWindow)
    }

    /// Rango de lectura recomendado para el almacén (`SQLiteStore.readings(in:)`).
    public var dataRange: ClosedRange<UTCInstant> { dataStart...end }

    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    enum CodingKeys: String, CodingKey {
        case start, end
        case timeZoneIdentifier = "time_zone"
    }
}
