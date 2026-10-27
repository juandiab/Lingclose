import SwiftUI

/// Pantalla provisional de Datos (T-06).
struct DataView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                String(localized: "data.title", defaultValue: "Datos"),
                systemImage: "externaldrive",
                description: Text(String(localized: "data.placeholder", defaultValue: "Aquí gestionarás Apple Salud, exportación y respaldo."))
            )
            .navigationTitle(String(localized: "data.title", defaultValue: "Datos"))
        }
    }
}

#Preview {
    DataView()
}
