import SwiftUI

/// Interruptor general de las alertas, arriba de su pantalla. Al activarlo se pide el permiso de notificaciones.
struct AlertMasterSection: View {
    @Bindable var alerts: AlertsController

    var body: some View {
        Section {
            Toggle(isOn: $alerts.settings.isEnabled) {
                Label(String(localized: "alerts.enabled", defaultValue: "Alertas de glucosa"), systemImage: "bell.badge")
            }
        } footer: {
            Text(String(localized: "alerts.footer", defaultValue: "Avisan si la glucosa sale del rango de referencia, cambia rápido o deja de llegar. Son informativas: Lingclose no es un dispositivo médico."))
        }
        .onChange(of: alerts.settings.isEnabled) { _, enabled in
            if enabled { requestPermission() }
        }
    }

    private func requestPermission() {
        Task { await alerts.requestPermissionIfNeeded() }
    }
}
