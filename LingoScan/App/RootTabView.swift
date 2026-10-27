import SwiftUI

/// Contenedor raíz con las cinco pestañas principales.
struct RootTabView: View {
    @State private var todayViewModel: TodayViewModel
    @State private var sensorViewModel: SensorViewModel
    @State private var ui: AppUIModels
    private let identityImport: IdentityImportModel?

    /// Fuentes reales: `SQLiteStore` y `SensorSessionCoordinator`.
    init(environment: AppEnvironment) {
        _todayViewModel = State(initialValue: TodayViewModel(
            dataSource: environment.todayData, sensorSource: environment.sensorStatus
        ))
        _sensorViewModel = State(initialValue: SensorViewModel(
            statusSource: environment.sensorStatus, actions: environment.sensorActions
        ))
        _ui = State(initialValue: environment.ui)
        identityImport = environment.identityImport
    }

    /// `PreviewData` (sintético y señalado como tal): `#Preview` y `-previewSensorState`.
    init(previewState: SensorPresentationState) {
        let data = PreviewData(sensorState: previewState)
        _todayViewModel = State(initialValue: TodayViewModel(dataSource: data, sensorSource: data))
        _sensorViewModel = State(initialValue: SensorViewModel(statusSource: data, actions: PreviewSensorActions()))
        _ui = State(initialValue: .preview(events: data.events))
        identityImport = nil
    }

    var body: some View {
        TabView {
            Tab(String(localized: "tab.today", defaultValue: "Hoy"), systemImage: "drop.fill") {
                TodayView(viewModel: todayViewModel, sensorViewModel: sensorViewModel)
            }
            Tab(String(localized: "tab.diary", defaultValue: "Diario"), systemImage: "book.closed") {
                DiaryView(viewModel: ui.diary)
            }
            Tab(String(localized: "tab.reports", defaultValue: "Reportes"), systemImage: "chart.xyaxis.line") {
                ReportsView()
            }
            Tab(String(localized: "tab.data", defaultValue: "Datos"), systemImage: "externaldrive") {
                DataView(viewModel: ui.data)
            }
            Tab(String(localized: "tab.settings", defaultValue: "Ajustes"), systemImage: "gearshape") {
                SettingsView(viewModel: ui.settings, identity: identityImport, alarms: ui.alarmModel)
            }
        }
        .modifier(IdentityImportAlert(model: identityImport))
    }
}

#Preview {
    RootTabView(previewState: .streaming)
}
