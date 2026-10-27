import Foundation

/// Tiempos de la sesión BLE. Valores iniciales de `docs/FORK_RWDK.md` §6 riesgo 6;
/// se calibran con el sensor de sacrificio (T-16).
struct SessionTimeouts: Sendable, Equatable {
    /// Conexión BLE. `.zero` = indefinida (petición pendiente que iOS conserva en segundo plano).
    var connect: Duration = .seconds(120)
    /// Ventana de escaneo cuando no hay `CBPeripheral.identifier` conocido.
    var scanWindow: Duration = .seconds(60)
    /// Respuesta a cada comando de seguridad de un byte (`PairingFlow`, por defecto 2 s).
    var command: Duration = .seconds(2)
    /// Confirmación de cada CCCD al activar el plano de datos.
    var cccd: Duration = .seconds(15)
    /// Sin trama de tiempo real válida durante este tiempo → `stale`.
    var stale: Duration = .seconds(300)
    /// Cadencia del vigilante de `stale`.
    var staleCheckInterval: Duration = .seconds(30)
    /// Espera inicial entre reintentos de conexión (se duplica hasta `maxReconnectBackoff`).
    var reconnectBackoff: Duration = .seconds(5)
    var maxReconnectBackoff: Duration = .seconds(300)
    /// Tiempo sin confirmación en `patchControl` tras el que se puede volver a pedir backfill.
    var backfillAck: Duration = .seconds(120)

    static let standard = SessionTimeouts()
}
