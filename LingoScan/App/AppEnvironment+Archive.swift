import Foundation
import LingoCore

/// Cableado del servicio de archivo `.lingoscan` (T-10) con el grafo de servicios.
///
/// Pendiente de quien posea `AppEnvironment.swift`: llamar `configureArchive(databaseURL:)` **una vez, al final de
/// `AppEnvironment.init`** (la tarea `BGAppRefreshTask` debe registrarse antes de que termine el lanzamiento, y
/// `AppEnvironment` se construye en `App.init`). Hasta entonces el servicio existe pero no hay tarea diaria.
extension AppEnvironment {
    private static var sharedArchiveService: ArchiveService?

    /// Servicio de archivo, creado una sola vez por proceso para la base de este entorno.
    func archiveService(databaseURL: URL) -> ArchiveService {
        if let existing = Self.sharedArchiveService { return existing }
        let service = ArchiveService(store: store, databasePath: databaseURL.path(percentEncoded: false))
        Self.sharedArchiveService = service
        return service
    }

    /// Crea el servicio, registra la tarea diaria, arranca el disparador en proceso y borra las `.partial` abandonadas.
    /// La tarea diaria se programa desde la última copia propia: llamar en cada arranque ya no la aplaza.
    @discardableResult
    func configureArchive(databaseURL: URL) -> ArchiveService {
        let service = archiveService(databaseURL: databaseURL)
        ArchiveBackgroundTask.register(
            work: { await service.exportIfDue() },
            lastExport: { await service.lastOwnExportDate() })
        ArchiveExportTrigger(service: service, store: store).install()
        Task {
            await service.removeAbandonedPartials()
            await ArchiveBackgroundTask.schedule(lastExport: await service.lastOwnExportDate())
        }
        return service
    }
}
