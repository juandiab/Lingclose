import SwiftUI

/// Ajustes › Conexiones › Apple Salud: qué hace Lingclose con Apple Salud, el estado del permiso (se pide en Datos) y
/// la importación de entrenamientos del Apple Watch.
struct HealthSettingsView: View {
    let isAuthorized: Bool

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: String(localized: "settings.permission.health", defaultValue: "Apple Salud"),
                    state: isAuthorized ? .granted : .notDetermined,
                    detail: isAuthorized ? nil : PermissionRow.healthDetail)
            } footer: {
                Text(String(localized: "settings.health.footer", defaultValue: "Lingclose guarda en Apple Salud tus lecturas válidas y lee de ahí tus entrenamientos y, para sugerir el rango, tu edad, sexo, peso y altura."))
            }
            WorkoutImportSection()
        }
        .navigationTitle(String(localized: "settings.permission.health", defaultValue: "Apple Salud"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HealthSettingsView(isAuthorized: false)
    }
}
