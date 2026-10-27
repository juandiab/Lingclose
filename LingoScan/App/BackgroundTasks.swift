import BackgroundTasks
import Foundation

/// Tarea periódica de la copia de seguridad (`BGAppRefreshTask`, una vez al día). iOS decide cuándo la ejecuta:
/// la exportación manual y la de fin de sensor no dependen de ella.
enum ArchiveBackgroundTask {
    /// Debe figurar en `BGTaskSchedulerPermittedIdentifiers` de `Info.plist` (ya está).
    static let refreshIdentifier = "com.otalvaro.lingoscan.archive.refresh"
    static let interval: TimeInterval = 24 * 3600

    /// Registra el manejador. **Debe llamarse antes de que termine el lanzamiento** (`App.init`): iOS aborta si se
    /// registra después. `work` devuelve si la exportación terminó bien; se ejecuta con la tarea ya en marcha.
    static func register(work: @escaping @Sendable () async -> Bool) {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
            let box = TaskBox(task)
            schedule()  // la siguiente, antes de empezar: si esta no termina, igualmente queda programada
            let job = Task {
                let ok = await work()
                box.task.setTaskCompleted(success: ok)
            }
            box.task.expirationHandler = { job.cancel() }
        }
        if !registered { assertionFailure("BGTaskScheduler ya tenía registrado \(refreshIdentifier)") }
    }

    /// Pide la próxima ejecución, no antes de `interval`. Idempotente: sustituye la solicitud pendiente.
    static func schedule(after interval: TimeInterval = ArchiveBackgroundTask.interval) {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
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
