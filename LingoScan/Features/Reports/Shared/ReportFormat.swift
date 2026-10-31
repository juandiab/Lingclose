import Foundation
import LingoCore

/// Formatos de Reportes: mg/dL enteros, porcentajes sin decimales, duraciones y fechas locales.
enum ReportFormat {
    /// "128"; `nil` sin dato.
    static func mgdl(_ value: Double?) -> String? {
        value.map { "\(Int($0.rounded()))" }
    }

    /// "62 %" para una fracción 0…1.
    static func percent(_ fraction: Double?) -> String? {
        fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) }
    }

    /// "+12" / "−5" / "0".
    static func signed(_ value: Double) -> String {
        let rounded = value.rounded()
        if rounded == 0 { return "0" }
        let magnitude = Int(abs(rounded))
        return rounded > 0 ? "+\(magnitude)" : "−\(magnitude)"
    }

    /// "1 h 20 min".
    static func duration(minutes: Int) -> String {
        Duration.seconds(max(0, minutes) * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// Hora del día para un minuto local ("6 a. m.", "18").
    static func hour(minute: Int) -> String {
        referenceDate(minute: minute).formatted(.dateTime.hour())
    }

    /// Hora y minutos para un minuto local ("23:00").
    static func clock(minute: Int) -> String {
        referenceDate(minute: minute).formatted(date: .omitted, time: .shortened)
    }

    /// "mié 28 oct".
    static func day(_ day: LocalDay) -> String {
        day.start.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "mié 28 oct, 7:30".
    static func dateTime(_ instant: UTCInstant) -> String {
        instant.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    /// "sáb 25 oct" para un día local ISO ("2026-10-25"); el propio texto si no se puede leer.
    static func localDate(_ iso: String) -> String {
        guard let date = try? Date(iso, strategy: Date.ISO8601FormatStyle().year().month().day()) else { return iso }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = .gmt
        return date.formatted(style)
    }

    /// "25–31 oct".
    static func range(_ period: ReportPeriod) -> String {
        let end = max(period.start.date, period.end.date.addingTimeInterval(-1))
        return (period.start.date..<end).formatted(.interval.day().month(.abbreviated))
    }

    private static func referenceDate(minute: Int) -> Date {
        Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(minute * 60))
    }
}
