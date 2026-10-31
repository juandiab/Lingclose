import Foundation
import LingoCore

/// Eventos de un día local, del más reciente al más antiguo.
struct DiaryDay: Identifiable, Hashable {
    /// Día de calendario `aaaa-mm-dd`: identidad estable de la sección de la lista aunque `start` se recalcule.
    let id: String
    /// Inicio del día en la zona horaria del dispositivo.
    let start: Date
    let events: [DiaryEvent]

    /// Clave del día de calendario de `date`.
    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
