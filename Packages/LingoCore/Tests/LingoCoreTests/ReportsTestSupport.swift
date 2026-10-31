import Foundation
@testable import LingoCore

/// Generador sintético para los tests de reportes (T-27a). Sin datos reales: valores, horas y textos inventados.
enum ReportsFixture {
    static let bogota = TimeZone(identifier: "America/Bogota")!
    static let newYork = TimeZone(identifier: "America/New_York")!

    static func instant(_ text: String) -> UTCInstant { UTCInstant(rfc3339: text)! }

    /// Días locales completos de `first` a `last` (`YYYY-MM-DD`) en `timeZone`.
    static func days(_ first: String, _ last: String, _ timeZone: TimeZone = bogota) -> ReportPeriod {
        ReportPeriod.days(from: noon(first, timeZone), through: noon(last, timeZone), timeZone: timeZone)
    }

    /// Mediodía local de `YYYY-MM-DD`.
    static func noon(_ day: String, _ timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = day.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    /// Instante de la hora local `hour:minute` del día `YYYY-MM-DD`.
    static func local(_ day: String, _ hour: Int, _ minute: Int = 0, _ timeZone: TimeZone = bogota) -> UTCInstant {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return UTCInstant(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: noon(day, timeZone))!)
    }

    /// Una lectura cada `step` segundos en `[from, to)`; `value` recibe el instante.
    static func series(from: UTCInstant, to: UTCInstant, step: Int64 = 60,
                       _ value: (UTCInstant) -> Int) -> [BasicStats.Sample] {
        stride(from: from.epochSeconds, to: to.epochSeconds, by: Int(step)).map {
            let t = UTCInstant(epochSeconds: $0)
            return BasicStats.Sample(measuredAt: t, valueMgdl: value(t))
        }
    }

    static func series(_ period: ReportPeriod, _ value: (UTCInstant) -> Int) -> [BasicStats.Sample] {
        series(from: period.start, to: period.end, value)
    }

    static func event(_ kind: DiaryEventKind, at: UTCInstant, carbs: Double? = nil, duration: Int? = nil,
                      text: String? = nil, id: String = UUID().uuidString.lowercased()) -> DiaryEvent {
        DiaryEvent(eventID: id, kind: kind, at: at, tz: "America/Bogota", durationMin: duration, carbsG: carbs, text: text,
                   createdAt: at, updatedAt: at, editID: UUID().uuidString.lowercased(),
                   editedByAppID: TestSupport.appID, synthetic: true)
    }

    /// Curva de comida de `AnalyticsMealResponseTests` (minuto relativo a la comida): base 100, pico 160 a los 45 min,
    /// 110 a los 110 min y 100 después.
    static func mealCurve(_ minute: Int) -> Int {
        switch minute {
        case ..<0: 100
        case 0...45: Int((100 + Double(minute) * 60 / 45).rounded())
        case 46...110: Int((160 - Double(minute - 45) * 50 / 65).rounded())
        default: 100
        }
    }

    /// Minutos desde el evento más reciente anterior o igual a `t` (o `nil`).
    static func minutesSinceLast(_ instants: [UTCInstant], _ t: UTCInstant) -> Int? {
        instants.filter { $0 <= t }.max().map { Int((t.epochSeconds - $0.epochSeconds) / 60) }
    }
}
