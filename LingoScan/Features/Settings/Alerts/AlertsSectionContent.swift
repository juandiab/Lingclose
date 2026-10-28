import SwiftUI

/// Contenido de `AlertsSection` con el controlador real.
struct AlertsSectionContent: View {
    @Bindable var alerts: AlertsController

    var body: some View {
        Section {
            Toggle(isOn: $alerts.settings.isEnabled) {
                Label(String(localized: "alerts.enabled", defaultValue: "Alertas de glucosa"), systemImage: "bell.badge")
            }
            NavigationLink {
                AlertsSettingsView(alerts: alerts)
            } label: {
                Text(String(localized: "alerts.configure", defaultValue: "Configurar alertas"))
            }
        } header: {
            Text(String(localized: "alerts.header", defaultValue: "Alertas"))
        } footer: {
            Text(String(localized: "alerts.footer", defaultValue: "Avisos informativos de alta, baja, cambios rápidos y falta de datos. LingoScan no es un dispositivo médico."))
        }
        .onChange(of: alerts.settings.isEnabled) { _, enabled in
            if enabled { requestPermission() }
        }
    }

    private func requestPermission() {
        Task { await alerts.requestPermissionIfNeeded() }
    }
}
