import Foundation

/// Tiempos de la sesión BLE. Valores iniciales de `docs/FORK_RWDK.md` §6 riesgo 6;
/// se calibran con el sensor de sacrificio (T-16).
struct SessionTimeouts: Sendable, Equatable {
    /// Conexión BLE del primer emparejamiento (en primer plano). `.zero` = indefinida.
    var connect: Duration = .seconds(120)
    /// Conexión BLE de las reconexiones: indefinida. Un tope finito cancela la petición pendiente de CoreBluetooth
    /// y, con la app en segundo plano, iOS la suspende durante la espera entre reintentos: la sesión queda varada
    /// hasta que el usuario vuelve a abrir la app (28-oct: dos huecos de una hora). La petición pendiente es lo que
    /// despierta a la app cuando el sensor vuelve a estar al alcance.
    var reconnect: Duration = .zero
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
    /// Tope corto: una espera larga sin petición BLE pendiente deja a la app suspendida en segundo plano.
    var maxReconnectBackoff: Duration = .seconds(30)
    /// Tiempo sin confirmación en `patchControl` tras el que se puede volver a pedir backfill.
    var backfillAck: Duration = .seconds(120)

    static let standard = SessionTimeouts()
}
