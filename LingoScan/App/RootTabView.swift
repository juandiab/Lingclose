import SwiftUI

/// Contenedor raíz con las cinco pestañas principales.
struct RootTabView: View {
    @State private var todayViewModel: TodayViewModel
    @State private var sensorViewModel: SensorViewModel
    private let identityImport: IdentityImportModel?

    /// Fuentes reales: `SQLiteStore` y `SensorSessionCoordinator`.
    init(environment: AppEnvironment) {
        _todayViewModel = State(initialValue: TodayViewModel(
            dataSource: environment.todayData, sensorSource: environment.sensorStatus
        ))
        _sensorViewModel = State(initialValue: SensorViewModel(
            statusSource: environment.sensorStatus, actions: environment.sensorActions
        ))
        identityImport = environment.identityImport
    }

    /// `PreviewData` (sintético y señalado como tal): `#Preview` y `-previewSensorState`.
    init(previewState: SensorPresentationState) {
        let data = PreviewData(sensorState: previewState)
        _todayViewModel = State(initialValue: TodayViewModel(dataSource: data, sensorSource: data))
        _sensorViewModel = State(initialValue: SensorViewModel(statusSource: data, actions: PreviewSensorActions()))
        identityImport = nil
    }

    var body: some View {
        TabView {
            Tab(String(localized: "tab.today", defaultValue: "Hoy"), systemImage: "drop.fill") {
                TodayView(viewModel: todayViewModel, sensorViewModel: sensorViewModel)
            }
            Tab(String(localized: "tab.diary", defaultValue: "Diario"), systemImage: "book.closed") {
                DiaryView()
            }
            Tab(String(localized: "tab.reports", defaultValue: "Reportes"), systemImage: "chart.xyaxis.line") {
                ReportsView()
            }
            Tab(String(localized: "tab.data", defaultValue: "Datos"), systemImage: "externaldrive") {
                DataView()
            }
            Tab(String(localized: "tab.settings", defaultValue: "Ajustes"), systemImage: "gearshape") {
                SettingsView(identity: identityImport)
            }
        }
        .modifier(IdentityImportAlert(model: identityImport))
    }
}

#Preview {
    RootTabView(previewState: .streaming)
}
