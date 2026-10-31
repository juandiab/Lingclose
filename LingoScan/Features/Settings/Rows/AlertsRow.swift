import SwiftUI

/// Ajustes › Lecturas › Alertas: estado (activadas o no) y enlace a su pantalla, donde está el interruptor general.
struct AlertsRow: View {
    @Environment(\.alerts) private var alerts

    var body: some View {
        if let alerts {
            NavigationLink(value: SettingsRoute.alerts) {
                LabeledContent {
                    Text(alerts.settings.isEnabled
                         ? String(localized: "alerts.state.on", defaultValue: "Activadas")
                         : String(localized: "alerts.state.off", defaultValue: "Desactivadas"))
                } label: {
                    SettingsRowTitle(title: String(localized: "alerts.title", defaultValue: "Alertas"), systemImage: "bell.badge")
                }
            }
        } else {
            SettingsRowTitle(
                title: String(localized: "alerts.title", defaultValue: "Alertas"),
                systemImage: "bell.slash",
                detail: String(localized: "alerts.unavailable", defaultValue: "No disponibles en la vista previa"))
        }
    }
}
