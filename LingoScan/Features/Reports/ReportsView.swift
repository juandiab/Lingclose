import SwiftUI

/// Pantalla provisional de Reportes (T-06).
struct ReportsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                String(localized: "reports.title", defaultValue: "Reportes"),
                systemImage: "chart.xyaxis.line",
                description: Text(String(localized: "reports.placeholder", defaultValue: "Aquí verás tus reportes de glucosa."))
            )
            .navigationTitle(String(localized: "reports.title", defaultValue: "Reportes"))
            .appBackground()
        }
    }
}

#Preview {
    ReportsView()
}
