import Foundation
import LingoCore
import Observation

/// Estado editable de las alertas para Ajustes. Guarda en `AlertSettingsStore` y avisa al servicio.
/// Una instancia por proceso, creada en `AppEnvironment.init` (también en relanzamientos en segundo plano).
@MainActor
@Observable
final class AlertsController {
    /// Editable desde Ajustes con `$alerts.settings…`: se normaliza, se guarda y el servicio reevalúa.
    var settings: AlertSettings {
        didSet {
            let clean = settings.normalized()
            if clean != settings { settings = clean; return }
            guard clean != oldValue else { return }
            store.saveSettings(clean)
            let service = service
            Task { await service.settingsDidChange() }
        }
    }
    private(set) var permission: AlertPermission = .notDetermined
    /// Resultado del último "Probar notificación".
    private(set) var testResult: TestResult?

    enum TestResult: Equatable { case sent, notAllowed }

    @ObservationIgnored let service: AlertService
    @ObservationIgnored private let store: AlertSettingsStore
    @ObservationIgnored private var installTask: Task<Void, Never>?

    init(service: AlertService, store: AlertSettingsStore) {
        self.service = service
        self.store = store
        self.settings = store.loadSettings()
    }

    /// Se suscribe a los estados del coordinador. Idempotente.
    func install(states: @escaping @Sendable () async -> AsyncStream<SessionState>) {
        guard installTask == nil else { return }
        let service = service
        installTask = Task { await service.observe(await states()) }
    }

    /// Llamar al encender el interruptor general: la primera vez pide permiso de notificaciones.
    func requestPermissionIfNeeded() async {
        await refreshPermission()
        guard permission == .notDetermined else { return }
        _ = await service.requestPermission()
        await refreshPermission()
    }

    /// Botón "Permitir notificaciones": enciende las alertas y pide permiso.
    func enableAndRequestPermission() async {
        settings.isEnabled = true
        await requestPermissionIfNeeded()
    }

    func refreshPermission() async {
        permission = await service.permission()
    }

    func sendTest() async {
        if permission == .notDetermined {
            _ = await service.requestPermission()
            await refreshPermission()
        }
        testResult = await service.sendTest() ? .sent : .notAllowed
    }

    /// Al volver a primer plano: reevalúa ("sin datos" incluido) y refresca el permiso.
    func sceneDidBecomeActive() {
        let service = service
        Task {
            await service.evaluate()
            await refreshPermission()
        }
    }
}
