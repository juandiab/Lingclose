import LingoCore

/// Lo único que "Conectar sensor activo" puede pedir: reconectar una sesión ya activada (importada) con
/// kAuth/PIN o, si hace falta, con el handshake completo. No hay camino a la activación NFC.
protocol RecoveryActiveSensorConnecting: Sendable {
    /// `state` es el `activation.state` importado; solo `response_saved` y `authenticated` se aceptan.
    func connectActiveSensor(importedState: ActivationState) async throws
}
