import LingoCore
import Observation
import SwiftUI

/// Estado editable de Ajustes > Alarmas. Persiste en el App Group y avisa al servicio.
@MainActor @Observable
final class AlarmSettingsModel {
    var settings: AlarmSettings {
        didSet {
            let clean = settings.normalized()
            if clean != settings { settings = clean; return }
            guard clean != oldValue else { return }
            store.save(clean)
            Task { [service] in await service.settingsDidChange() }
        }
    }
    private(set) var permission: AlarmPermission = .notDetermined

    @ObservationIgnored private let store: AlarmSettingsStore
    @ObservationIgnored private let service: AlarmService

    init(store: AlarmSettingsStore, service: AlarmService) {
        self.store = store
        self.service = service
        self.settings = store.load()
    }

    func refreshPermission() async {
        permission = await service.permission()
    }

    func requestPermission() async {
        _ = await service.requestPermission()
        await refreshPermission()
    }
}

struct AlarmsSettingsView: View {
    @Bindable var model: AlarmSettingsModel

    var body: some View {
        Form {
            Section {
                Text(String(localized: "alarms.disclaimer", defaultValue: "LingoScan no es un dispositivo médico; estas alarmas son informativas"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section(String(localized: "alarms.permission.title", defaultValue: "Notificaciones")) {
                switch model.permission {
                case .authorized:
                    Label(String(localized: "alarms.permission.on", defaultValue: "Permitidas"), systemImage: "checkmark.circle")
                case .notDetermined:
                    Button(String(localized: "alarms.permission.ask", defaultValue: "Permitir notificaciones")) {
                        Task { await model.requestPermission() }
                    }
                case .denied:
                    Text(String(localized: "alarms.permission.denied", defaultValue: "Desactivadas en Ajustes de iOS. Actívalas para recibir alarmas."))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle(String(localized: "alarms.low.toggle", defaultValue: "Alarma baja"), isOn: $model.settings.lowEnabled)
                Stepper(value: $model.settings.lowMgdl, in: AlarmSettings.lowRange, step: 5) {
                    LabeledContent(String(localized: "alarms.low.threshold", defaultValue: "Umbral bajo"), value: "\(model.settings.lowMgdl) mg/dL")
                }
                .disabled(!model.settings.lowEnabled)
            } footer: {
                Text(String(localized: "alarms.low.footer", defaultValue: "La alarma baja puede sonar aunque tengas un modo de concentración activo."))
            }
            Section {
                Toggle(String(localized: "alarms.high.toggle", defaultValue: "Alarma alta"), isOn: $model.settings.highEnabled)
                Stepper(value: $model.settings.highMgdl, in: AlarmSettings.highRange, step: 5) {
                    LabeledContent(String(localized: "alarms.high.threshold", defaultValue: "Umbral alto"), value: "\(model.settings.highMgdl) mg/dL")
                }
                .disabled(!model.settings.highEnabled)
            }
            Section {
                Toggle(String(localized: "alarms.nodata.toggle", defaultValue: "Aviso de sin datos"), isOn: $model.settings.noDataEnabled)
                Stepper(value: $model.settings.noDataMinutes, in: AlarmSettings.noDataRange, step: 5) {
                    LabeledContent(String(localized: "alarms.nodata.minutes", defaultValue: "Tras"), value: "\(model.settings.noDataMinutes) min")
                }
                .disabled(!model.settings.noDataEnabled)
            } footer: {
                Text(String(localized: "alarms.repeat.footer", defaultValue: "Cada alarma no se repite hasta pasados 15 minutos."))
            }
        }
        .navigationTitle(String(localized: "alarms.title", defaultValue: "Alarmas"))
        .task { await model.refreshPermission() }
    }
}

#Preview {
    NavigationStack {
        AlarmsSettingsView(model: AlarmSettingsModel(
            store: AlarmSettingsStore(defaults: UserDefaults(suiteName: "preview.alarms") ?? .standard),
            service: AlarmService(settings: AlarmSettingsStore(defaults: UserDefaults(suiteName: "preview.alarms") ?? .standard))
        ))
    }
}
