import BackgroundTasks
import Foundation

/// Tarea periódica de la copia de seguridad (`BGAppRefreshTask`, una vez al día). iOS decide cuándo la ejecuta (y
/// puede tardar días): `ArchiveExportTrigger` cubre el caso en proceso; la exportación manual y la de fin de sensor
/// tampoco dependen de ella.
enum ArchiveBackgroundTask {
    /// Debe figurar en `BGTaskSchedulerPermittedIdentifiers` de `Info.plist` (ya está).
    static let refreshIdentifier = "com.otalvaro.lingoscan.archive.refresh"
    static let interval: TimeInterval = 24 * 3600

    /// Registra el manejador. **Debe llamarse antes de que termine el lanzamiento** (`App.init`): iOS aborta si se
    /// registra después. `work` devuelve si la exportación terminó bien; se ejecuta con la tarea ya en marcha.
    /// `lastExport` da la fecha de la última copia propia para programar la siguiente.
    static func register(
        work: @escaping @Sendable () async -> Bool,
        lastExport: @escaping @Sendable () async -> Date?
    ) {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
            let box = TaskBox(task)
            let job = Task {
                // La solicitud que nos lanzó ya se consumió: dejar una antes de empezar por si esta no termina.
                await schedule(lastExport: await lastExport())
                let ok = await work()
                // Con la copia recién hecha (o fallida) la fecha correcta cambia: se sustituye la pendiente.
                await schedule(lastExport: await lastExport(), replacingPending: true)
                box.task.setTaskCompleted(success: ok)
            }
            box.task.expirationHandler = { job.cancel() }
        }
        if !registered { assertionFailure("BGTaskScheduler ya tenía registrado \(refreshIdentifier)") }
    }

    /// Pide la próxima ejecución en `lastExport + interval` (mínimo dentro de 15 min, `ArchiveSchedulePolicy`).
    /// Si ya hay una solicitud pendiente con fecha igual o anterior no la toca, salvo `replacingPending`: llamar en
    /// cada arranque del proceso ya no aplaza la copia.
    static func schedule(
        lastExport: Date?,
        now: Date = .now,
        interval: TimeInterval = ArchiveBackgroundTask.interval,
        replacingPending: Bool = false
    ) async {
        let desired = ArchiveSchedulePolicy.earliestBeginDate(now: now, lastExport: lastExport, interval: interval)
        if !replacingPending {
            let pending: Date?? = await BGTaskScheduler.shared.pendingTaskRequests()
                .first { $0.identifier == refreshIdentifier }
                .map(\.earliestBeginDate)
            guard ArchiveSchedulePolicy.shouldSubmit(desired: desired, pending: pending) else { return }
        }
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = desired
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
    }

    /// `BGTask` no es `Sendable`; el sistema lo entrega y solo se usa para completarlo y para su caducidad.
    private final class TaskBox: @unchecked Sendable {
        let task: BGTask
        init(_ task: BGTask) { self.task = task }
    }
}
