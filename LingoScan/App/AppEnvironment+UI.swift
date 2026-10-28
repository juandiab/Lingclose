import Foundation
import LingoCore
import Observation

/// View models de Diario, Datos y Ajustes.
@MainActor
@Observable
final class AppUIModels {
    let diary: DiaryViewModel
    let data: DataViewModel
    let settings: SettingsViewModel

    init(diary: DiaryViewModel, data: DataViewModel, settings: SettingsViewModel) {
        self.diary = diary
        self.data = data
        self.settings = settings
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

    /// Modelos de las pantallas, creados una sola vez por proceso. Las alertas (T-24) no dependen de esto: se crean en
    /// `init` (`AppEnvironment+Alerts`).
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
        return models
    }
}
