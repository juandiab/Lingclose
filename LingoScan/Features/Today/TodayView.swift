import SwiftUI

/// Pantalla provisional de Hoy (T-06).
struct TodayView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                String(localized: "today.title", defaultValue: "Hoy"),
                systemImage: "drop.fill",
                description: Text(String(localized: "today.placeholder", defaultValue: "Aquí verás tu glucosa actual."))
            )
            .navigationTitle(String(localized: "today.title", defaultValue: "Hoy"))
        }
    }
}

#Preview {
    TodayView()
}
