import Foundation

/// Cálculo puro de cuándo pedir la próxima `BGAppRefreshTask` de la copia diaria.
///
/// La fecha sale de la última copia propia, no del momento en que se llama: así relanzar el proceso (aperturas,
/// relanzamientos de CoreBluetooth en segundo plano, cierres) ya no empuja la tarea otras 24 h.
enum ArchiveSchedulePolicy {
    /// Margen mínimo desde ahora: iOS no ejecuta antes de unos minutos y una fecha pasada no aporta nada.
    static let minimumLead: TimeInterval = 15 * 60

    /// `lastExport + interval`, nunca antes de `now + minimumLead`. Sin copia previa (o vencida): `now + minimumLead`.
    static func earliestBeginDate(now: Date, lastExport: Date?, interval: TimeInterval) -> Date {
        let floor = now.addingTimeInterval(minimumLead)
        guard let lastExport else { return floor }
        return max(lastExport.addingTimeInterval(interval), floor)
    }

    /// Si hay que enviar la solicitud: no se reenvía si ya hay una pendiente con fecha igual o anterior
    /// (una pendiente sin fecha cuenta como "lo antes posible").
    static func shouldSubmit(desired: Date, pending: Date??) -> Bool {
        switch pending {
        case .none: true                       // no hay solicitud pendiente
        case .some(.none): false               // pendiente sin fecha: ya es la más temprana posible
        case .some(.some(let date)): date > desired
        }
    }
}
