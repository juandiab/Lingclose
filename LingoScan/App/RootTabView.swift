import SwiftUI

/// Contenedor raíz con las cinco pestañas principales.
struct RootTabView: View {
    var body: some View {
        TabView {
            Tab(String(localized: "tab.today", defaultValue: "Hoy"), systemImage: "drop.fill") {
                TodayView()
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
