import Foundation
import LingoCore

/// Propiedades editables para enlazar los controles de Ajustes con `$alerts.settings…` sin `Binding(get:set:)`.
extension AlertSettings {
    subscript(enabled kind: AlertKind) -> Bool {
        get { isEnabled(kind) }
        set { setEnabled(newValue, for: kind) }
    }

    /// Un solo silencio entre avisos para alta, baja, subida y bajada; "sin datos" conserva el suyo (60 min).
    var sharedCooldownMinutes: Int {
        get { cooldown(for: .high) }
        set { for kind in AlertKind.allCases where kind != .noData { setCooldown(newValue, for: kind) } }
    }

    var quietHoursEnabled: Bool {
        get { quietHours != nil }
        set { quietHours = newValue ? (quietHours ?? .night) : nil }
    }

    /// Inicio y fin de las horas de silencio como `Date` de hoy (para `DatePicker` de hora).
    var quietStart: Date {
        get { Self.date(minuteOfDay: quietHours?.startMinute ?? QuietHours.night.startMinute) }
        set { if let q = quietHours { quietHours = QuietHours(startMinute: Self.minuteOfDay(newValue), endMinute: q.endMinute) } }
    }

    var quietEnd: Date {
        get { Self.date(minuteOfDay: quietHours?.endMinute ?? QuietHours.night.endMinute) }
        set { if let q = quietHours { quietHours = QuietHours(startMinute: q.startMinute, endMinute: Self.minuteOfDay(newValue)) } }
    }

    private static func date(minuteOfDay minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
