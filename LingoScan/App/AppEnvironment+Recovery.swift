import Foundation

extension AppEnvironment {
    /// Construye `RecoveryService` sobre el almacén de pairing, las credenciales y SQLite de la app,
    /// lo conecta al `LiveRecoveryExportHook` del `PairingStateStore` (si es ese el hook instalado) y lo
    /// registra para las vistas. Idempotente.
    ///
    /// Para que la exportación en `prepared`/`response_saved`/`authenticated` funcione en la app, el `init`
    /// de `AppEnvironment` debe crear `PairingStateStore(recoveryHook: LiveRecoveryExportHook(fallback:
    /// EventLogRecoveryExportHook(store: store)))` y llamar a `installRecovery()` (ver `docs/T-19.md`).
    @discardableResult
    func installRecovery() -> RecoveryService {
        if let current = RecoveryContext.current, current.connector != nil { return current.service }
        let service = RecoveryService(pairingStore: pairingStore, credentials: credentials, store: store)
        RecoveryContext.current = RecoveryContext(
            service: service, connector: RecoveryLiveSensorConnector(coordinator: coordinator)
        )
        Task {
            if let hook = pairingStore.recoveryHook as? LiveRecoveryExportHook { await hook.attach(service) }
            await service.start()
        }
        return service
    }

    /// `true` si el `PairingStateStore` exporta de verdad en las transiciones (no el hook provisional).
    var recoveryHookIsLive: Bool { pairingStore.recoveryHook is LiveRecoveryExportHook }
}
