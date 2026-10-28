import Foundation
import LingoCore

extension AppEnvironment {
    /// Alertas de glucosa (T-24). Se crean en `init` para que existan también cuando iOS relanza la app en segundo
    /// plano por BLE: el servicio escucha los estados del coordinador, que emite uno por cada lectura en vivo guardada.
    static func makeAlerts(store: SQLiteStore, coordinator: SensorSessionCoordinator) -> AlertsController {
        AlertNotificationDelegate.install()
        let settingsStore = AlertSettingsStore.appGroup()
        let service = AlertService(
            data: store, notifier: AlertNotifier(), settingsStore: settingsStore,
            thresholds: { referenceThresholds(UserDefaults.standard) })
        let controller = AlertsController(service: service, store: settingsStore)
        controller.install { await coordinator.states() }
        return controller
    }

    /// Líneas del rango de referencia (Ajustes → Rango de referencia, `AppStorage` en `standard`): alta y baja de las alertas.
    nonisolated static func referenceThresholds(_ defaults: UserDefaults) -> (low: Int, high: Int) {
        let low = defaults.object(forKey: ReferenceLines.lowKey) as? Int ?? ReferenceLines.defaultLow
        let high = defaults.object(forKey: ReferenceLines.highKey) as? Int ?? ReferenceLines.defaultHigh
        return ReferenceLines.normalized(low: low, high: high)
    }
}
