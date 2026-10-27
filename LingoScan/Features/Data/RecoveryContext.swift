import Foundation

/// Servicio de recuperación y conector que usan las vistas de Datos y "Conectar sensor activo".
/// `AppEnvironment.installRecovery()` lo registra con los servicios reales; si aún no se ha llamado,
/// `resolve()` crea un servicio autónomo sobre los mismos archivos y Keychain (sin conector BLE).
@MainActor
struct RecoveryContext {
    let service: RecoveryService
    let connector: (any RecoveryActiveSensorConnecting)?

    static var current: RecoveryContext?

    static func resolve() -> RecoveryContext {
        if let current { return current }
        let standalone = RecoveryContext(
            service: RecoveryService(
                pairingStore: PairingStateStore(recoveryHook: LiveRecoveryExportHook()),
                credentials: CredentialStore(),
                store: nil
            ),
            connector: nil
        )
        current = standalone
        return standalone
    }
}
