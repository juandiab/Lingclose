import Foundation
import LingoCore

/// Eventos de un día local, del más reciente al más antiguo.
struct DiaryDay: Identifiable, Hashable {
    /// Inicio del día en la zona horaria del dispositivo.
    let start: Date
    let events: [DiaryEvent]

    var id: Date { start }
}
