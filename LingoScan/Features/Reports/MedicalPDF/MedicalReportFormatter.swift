import Foundation
import LingoCore

/// Formatos del reporte para el médico (T-34): números y fechas con el locale y la zona del período, y glucosa en la
/// unidad elegida. Lo que falta se escribe "—".
struct MedicalReportFormatter: Sendable {
    static let dash = "—"

    let locale: Locale
    let timeZone: TimeZone
    let unit: MedicalGlucoseUnit

    init(locale: Locale = .current, timeZone: TimeZone = .current, unit: MedicalGlucoseUnit = .mgdl) {
        self.locale = locale
        self.timeZone = timeZone
        self.unit = unit
    }

    // MARK: Números

    /// Con exactamente `decimals` decimales.
    func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).grouping(.never).locale(locale))
    }

    /// Hasta `maxDecimals` decimales, sin ceros de relleno ("80", "2,5").
    func flexible(_ value: Double, maxDecimals: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxDecimals)).grouping(.never).locale(locale))
    }

    /// Con signo explícito: "+12", "−5", "0".
    func signed(_ value: Double, decimals: Int = 0) -> String {
        let rounded = (value * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        if rounded == 0 { return number(0, decimals: decimals) }
        let magnitude = number(abs(rounded), decimals: decimals)
        return rounded > 0 ? "+\(magnitude)" : "−\(magnitude)"
    }

    func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(locale))
    }

    /// Fracción 0…1 como porcentaje: "62 %".
    func percent(_ fraction: Double?, decimals: Int = 0) -> String {
        guard let fraction else { return Self.dash }
        return number(fraction * 100, decimals: decimals) + " %"
    }

    // MARK: Glucosa

    /// Valor de glucosa (viene en mg/dL) en la unidad del reporte, sin símbolo.
    func glucose(_ mgdl: Double?) -> String {
        guard let mgdl else { return Self.dash }
        return number(unit.converted(mgdl), decimals: unit.decimals)
    }

    /// Cambio de glucosa con signo en la unidad del reporte.
    func glucoseDelta(_ mgdl: Double?) -> String {
        guard let mgdl else { return Self.dash }
        return signed(unit.converted(mgdl), decimals: unit.decimals)
    }

    // MARK: Tiempo

    /// "1 h 20 min", "45 min", "2 h".
    func duration(minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60, rest = total % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// Minutos por día a partir de una fracción del tiempo: "3 h 12 min", "0 min".
    func timePerDay(fraction: Double) -> String {
        duration(minutes: Int((fraction * 1_440).rounded()))
    }

    // MARK: Fechas

    private func style() -> Date.FormatStyle {
        Date.FormatStyle(date: nil, time: nil, locale: locale, calendar: calendar, timeZone: timeZone)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    /// "3 nov, 13:10".
    func dayAndTime(_ date: Date) -> String {
        date.formatted(style().day().month(.abbreviated).hour().minute())
    }

    /// "lun 3 nov".
    func weekdayDay(_ date: Date) -> String {
        date.formatted(style().weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "3 nov".
    func shortDay(_ date: Date) -> String {
        date.formatted(style().day().month(.abbreviated))
    }

    /// "3 de noviembre de 2026".
    func longDate(_ date: Date) -> String {
        date.formatted(style().day().month(.wide).year())
    }

    /// "3 nov 2026".
    func mediumDate(_ date: Date) -> String {
        date.formatted(style().day().month(.abbreviated).year())
    }

    /// "3 nov 2026, 13:10" (el pie del PDF).
    func fullDateTime(_ date: Date) -> String {
        date.formatted(style().day().month(.abbreviated).year().hour().minute())
    }

    /// Un día local ISO ("2026-10-25") como "dom 25 oct"; el propio texto si no se puede leer.
    func weekdayDay(iso: String) -> String {
        guard let date = Self.isoDay(iso, timeZone: timeZone) else { return iso }
        return weekdayDay(date)
    }

    /// "25 oct – 7 nov 2026".
    func periodRange(_ period: ReportPeriod) -> String {
        let last = max(period.start.date, period.end.date.addingTimeInterval(-1))
        let first = period.start.date
        if calendar.isDate(first, inSameDayAs: last) { return mediumDate(first) }
        let sameYear = calendar.component(.year, from: first) == calendar.component(.year, from: last)
        let left = sameYear ? shortDay(first) : mediumDate(first)
        return "\(left) – \(mediumDate(last))"
    }

    /// "2026-10-25" para el nombre del archivo.
    func isoDay(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
    }

    /// Mediodía local del día ISO, para formatearlo sin saltar de día por la zona.
    static func isoDay(_ iso: String, timeZone: TimeZone) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
