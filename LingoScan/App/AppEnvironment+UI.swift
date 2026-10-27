import Foundation
import LingoCore
import Observation

/// View models de Diario, Datos y Ajustes, y el `AlarmRuntime` (que hay que retener mientras viva la app).
@MainActor
@Observable
final class AppUIModels {
    let diary: DiaryViewModel
    let data: DataViewModel
    let settings: SettingsViewModel
    /// Servicio de alarmas enlazado al coordinador. Se crea de forma asíncrona al arrancar.
    private(set) var alarmRuntime: AlarmRuntime?

    var alarmModel: AlarmSettingsModel? { alarmRuntime?.model }

    init(diary: DiaryViewModel, data: DataViewModel, settings: SettingsViewModel) {
        self.diary = diary
        self.data = data
        self.settings = settings
    }

    func attach(_ runtime: AlarmRuntime) {
        alarmRuntime = runtime
    }

    /// Previsualización: diario con los eventos sintéticos (rotulados) y el resto inerte.
    static func preview(events: [DiaryEvent]) -> AppUIModels {
        let health = PreviewHealthController()
        return AppUIModels(
            diary: DiaryViewModel(store: InMemoryDiaryStore(events: events)),
            data: DataViewModel(archive: PreviewArchiveManager(), health: health, eventLog: EmptyEventLog()),
            settings: SettingsViewModel(health: health))
    }
}

extension AppEnvironment {
    private static var sharedUI: AppUIModels?

    /// Modelos de las pantallas, creados una sola vez por proceso. Al crearlos arranca el servicio de alarmas
    /// (para que funcionen sin abrir Ajustes) y queda retenido aquí.
    var ui: AppUIModels {
        if let existing = Self.sharedUI { return existing }
        let databaseURL = (try? Self.defaultDatabaseURL()) ?? URL.temporaryDirectory.appending(path: "lingoscan.sqlite")
        let fillGaps = FillGapsSwitch()
        let exporter = makeHealthExporter(policy: { HealthExportPolicy(fillGaps: fillGaps.isOn) })
        let sensorStatus = sensorStatus
        let health = LiveHealthController(
            exporter: exporter, fillGapsSwitch: fillGaps,
            isPaused: { await sensorStatus.currentStatus().state == .paused })
        let models = AppUIModels(
            diary: DiaryViewModel(store: SQLiteDiaryStore(store: store)),
            data: DataViewModel(
                archive: LiveArchiveManager(service: archiveService(databaseURL: databaseURL)),
                health: health, eventLog: store),
            settings: SettingsViewModel(health: health))
        Self.sharedUI = models
        Task { models.attach(await makeAlarmRuntime()) }
        return models
    }
}
