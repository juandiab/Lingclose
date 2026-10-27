import Foundation

/// Acciones reales del sensor (`LiveSensorActions`) o de previsualización. El view model no
/// contiene lógica de protocolo: solo llama aquí.
@MainActor
protocol SensorActions: AnyObject {
    /// NFC `0xA1` solo lectura. El estado resultante llega por `SensorStatusSource`.
    func readSensor() async throws
    /// Qué falta en credenciales para poder activar; `nil` si nada.
    func credentialBlocker() async -> ActivationBlocker?
    /// Genera y persiste el Receiver ID (sesión `prepared`) y devuelve lo que se mostrará.
    func prepareActivation() async throws -> ActivationSummary
    /// Convierte la confirmación en `ActivationTicket` y envía `0xA0`.
    func activate(_ confirmation: ActivationConfirmation) async throws
}
