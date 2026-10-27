import Foundation

/// Lo que la UI muestra de un fallo de autenticación. Sin secretos ni bytes crudos.
struct SensorFailureDetail: Sendable, Hashable {
    /// Fase en la que falló, ya en texto ("Conexión BLE", "Certificado del sensor"…).
    var phase: String
    /// Motivo corto (`AuthenticationFailureReason.summary`).
    var summary: String
    /// La app murió entre `sent` y `response_saved`: no se reenvía `0xA0` automáticamente.
    var isIncompleteAttempt: Bool
    /// Corte o timeout: no indica credenciales equivocadas.
    var isInterruption: Bool
}
