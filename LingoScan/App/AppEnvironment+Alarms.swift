import Foundation

/// Servicio de alarmas, su modelo de Ajustes y la conexión con el coordinador.
@MainActor
final class AlarmRuntime {
    let service: AlarmService
    let model: AlarmSettingsModel

    init(service: AlarmService, model: AlarmSettingsModel) {
        self.service = service
        self.model = model
    }
}

extension AppEnvironment {
    /// Construye el servicio con el App Group real y lo suscribe a los estados del coordinador.
    /// Quien llama conserva el `AlarmRuntime` (p. ej. el árbol de Ajustes) mientras viva la app.
    func makeAlarmRuntime(
        store: AlarmSettingsStore = .appGroup(),
        scheduler: any NotificationScheduling = SystemNotificationScheduler()
    ) async -> AlarmRuntime {
        let service = AlarmService(settings: store, scheduler: scheduler)
        await service.observe(await coordinator.states())
        return AlarmRuntime(service: service, model: AlarmSettingsModel(store: store, service: service))
    }
}
