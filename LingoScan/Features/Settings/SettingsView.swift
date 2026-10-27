import SwiftUI

/// Pantalla provisional de Ajustes (T-06).
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                String(localized: "settings.title", defaultValue: "Ajustes"),
                systemImage: "gearshape",
                description: Text(String(localized: "settings.placeholder", defaultValue: "Aquí ajustarás unidades, alarmas y permisos."))
            )
            .navigationTitle(String(localized: "settings.title", defaultValue: "Ajustes"))
        }
    }
}

#Preview {
    SettingsView()
}
