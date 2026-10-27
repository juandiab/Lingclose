import Foundation
import RoundWhiteDiscKit

/// Abstrae `SensorScanner` + `SensorSession` + el transporte de `PairingFlow` del fork
/// para poder inyectar dobles guionados en los tests. El coordinador ejecuta
/// `PairingFlow` sobre `pairingTransport()`.
protocol SensorLink: Sendable {
    /// Identificadores de periféricos que CoreBluetooth restauró al relanzar la app.
    func restoredPeripheralIDs() async -> [UUID]
    /// Conecta (o retoma un periférico restaurado), descubre servicios y suscribe
    /// las características del handshake. Devuelve `CBPeripheral.identifier`.
    func connect(peripheralID: UUID?, timeout: Duration, scanWindow: Duration) async throws -> UUID
    func isConnected() async -> Bool
    /// Transporte de comandos de seguridad para `PairingFlow` sobre la conexión actual.
    func pairingTransport() async throws -> any CommandPairingTransport
    /// CCCD del plano de datos en el orden de `docs/PROTOCOLO_LINGO.md` §0.2, incluidas
    /// `historicData` y `clinicalData` (`docs/FORK_RWDK.md` §6 riesgo 5).
    func enableDataPlaneNotifications(timeout: Duration) async throws
    /// Eventos de la conexión actual (con búfer desde `connect`).
    func events() async -> AsyncStream<SensorLinkEvent>
    /// Escribe una trama cifrada de 13 B en `patchControl`.
    func writePatchControl(_ frame: Data) async throws
    func disconnect() async
}
