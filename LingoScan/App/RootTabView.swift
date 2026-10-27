import SwiftUI

/// Contenedor raíz con las cinco pestañas principales.
struct RootTabView: View {
    @State private var todayViewModel: TodayViewModel
    @State private var sensorViewModel: SensorViewModel

    /// Mientras T-08 y `SQLiteStore` no tengan adaptador, la app usa `PreviewData` (sintético y señalado como tal en pantalla).
    init() {
        let data = PreviewData(sensorState: PreviewData.launchSensorState ?? .streaming)
        _todayViewModel = State(initialValue: TodayViewModel(dataSource: data, sensorSource: data))
        let sensor = SensorViewModel(statusSource: data)
        #if DEBUG
        // Acciones de ejemplo solo en depuración para poder ver la pantalla de activación; no envían nada.
        sensor.readSensorAction = {}
        sensor.activateAction = { _ in }
        #endif
        _sensorViewModel = State(initialValue: sensor)
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
                SettingsView()
            }
        }
    }
}

#Preview {
    RootTabView()
}
