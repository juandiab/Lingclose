import SwiftUI

/// Ajustes › Conexiones › Apple Salud: si hay permiso y enlace a su pantalla (permiso y entrenamientos).
struct HealthRow: View {
    let isAuthorized: Bool

    var body: some View {
        NavigationLink(value: SettingsRoute.health) {
            LabeledContent {
                Text(isAuthorized
                     ? String(localized: "settings.health.connected", defaultValue: "Conectada")
                     : String(localized: "settings.health.notConnected", defaultValue: "Sin permiso"))
            } label: {
                SettingsRowTitle(title: String(localized: "settings.permission.health", defaultValue: "Apple Salud"),
                                 systemImage: "heart.text.square")
            }
        }
    }
}
