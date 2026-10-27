import LingoCore

/// Hook real de recuperación (`RECUPERACION_V1.md` §4): tras persistir `prepared`, `response_saved` y
/// `authenticated`, exporta el archivo cifrado con `sequence` incrementada (`RecoveryService.checkpoint`).
///
/// `PairingStateStore` recibe el hook en su `init`, antes de que exista `RecoveryService` (que a su vez
/// necesita el almacén); por eso el servicio se conecta después con `attach`. Mientras no haya servicio,
/// los puntos de control se guardan y se entregan al conectar, y `fallback` deja constancia en `event_log`.
/// Sin frase en memoria, el servicio los deja como exportación pendiente y la UI lo muestra.
actor LiveRecoveryExportHook: RecoveryExportHook {
    private let fallback: (any RecoveryExportHook)?
    private var service: RecoveryService?
    private var queued: [ActivationRecord] = []

    init(fallback: (any RecoveryExportHook)? = nil, service: RecoveryService? = nil) {
        self.fallback = fallback
        self.service = service
    }

    func attach(_ service: RecoveryService) async {
        self.service = service
        let pending = queued
        queued = []
        for record in pending { await service.checkpoint(record) }
    }

    func recoveryCheckpoint(_ record: ActivationRecord) async {
        guard ActivationRecord.exportStates.contains(record.state) else { return }
        if let service {
            await service.checkpoint(record)
        } else {
            queued.append(record)
            await fallback?.recoveryCheckpoint(record)
        }
    }
}
