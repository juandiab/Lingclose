import Foundation
import RoundWhiteDiscKit

/// Evento del plano de datos de una conexión BLE.
enum SensorLinkEvent: Sendable, Equatable {
    /// Notificación cruda de una característica del plano de datos.
    case fragment(DataPlaneChannel, Data)
    /// El enlace se cerró; el flujo de eventos de esta conexión termina después.
    case disconnected
}
