import Foundation
import LingoCore

/// Compone título y cuerpo de cada aviso. `tip` (T-25: primer consejo de `CoachingRules`, si "Incluir consejos" está
/// activado) se añade en una línea al final del cuerpo.
struct AlertMessageComposer: Sendable {
    var timeZone: TimeZone = .current
    var locale: Locale = .current

    func notification(for event: AlertEvent, low: Int, high: Int, tip: String? = nil) -> AlertNotification {
        let (title, body) = text(for: event, low: low, high: high)
        let fullBody = [body, tip].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "\n")
        return AlertNotification(
            id: "lingoscan.alert.\(event.kind.rawValue).\(event.at.epochSeconds)",
            kind: event.kind, title: title, body: fullBody,
            isTimeSensitive: event.kind == .low || event.kind == .fallingFast)
    }

    /// Notificación de ejemplo para "Probar notificación".
    func testNotification(at date: Date, tip: String? = nil) -> AlertNotification {
        let body = String(localized: "alert.test.body", defaultValue: "Así se verán las alertas. Subiendo 2,4 mg/dL por minuto desde las \(time(date)).")
        return AlertNotification(
            id: "lingoscan.alert.test.\(Int(date.timeIntervalSince1970))", kind: nil,
            title: String(localized: "alert.test.title", defaultValue: "Prueba: glucosa alta, 165 mg/dL"),
            body: [body, tip].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "\n"),
            isTimeSensitive: false)
    }

    func text(for event: AlertEvent, low: Int, high: Int) -> (title: String, body: String) {
        let value = event.value ?? 0
        let since = time((event.since ?? event.at).date)
        let slope = event.slopePerMinute
        switch event.kind {
        case .high:
            let title = String(localized: "alert.high.title", defaultValue: "Glucosa alta: \(value) mg/dL")
            if let slope, slope >= 1 {
                return (title, rising(slope, since: since))
            }
            return (title, String(localized: "alert.high.body", defaultValue: "Por encima de \(high) mg/dL desde las \(since)."))
        case .low:
            let title = String(localized: "alert.low.title", defaultValue: "Glucosa baja: \(value) mg/dL")
            if let slope, slope <= -1 {
                return (title, falling(slope, since: since))
            }
            return (title, String(localized: "alert.low.body", defaultValue: "Por debajo de \(low) mg/dL desde las \(since)."))
        case .risingFast:
            return (String(localized: "alert.risingFast.title", defaultValue: "Subida rápida: \(value) mg/dL"),
                    rising(slope ?? 0, since: since))
        case .fallingFast:
            return (String(localized: "alert.fallingFast.title", defaultValue: "Bajada rápida: \(value) mg/dL"),
                    falling(slope ?? 0, since: since))
        case .noData:
            return (String(localized: "alert.noData.title", defaultValue: "Sin datos del sensor"),
                    String(localized: "alert.noData.body", defaultValue: "Sin lecturas desde las \(since). Acerca el iPhone al sensor."))
        }
    }

    private func rising(_ slope: Double, since: String) -> String {
        String(localized: "alert.rising.body", defaultValue: "Subiendo \(rate(slope)) mg/dL por minuto desde las \(since).")
    }

    private func falling(_ slope: Double, since: String) -> String {
        String(localized: "alert.falling.body", defaultValue: "Bajando \(rate(slope)) mg/dL por minuto desde las \(since).")
    }

    /// Valor absoluto con un decimal en la convención del idioma (2,4 en español).
    func rate(_ slope: Double) -> String {
        abs(slope).formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    func time(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
