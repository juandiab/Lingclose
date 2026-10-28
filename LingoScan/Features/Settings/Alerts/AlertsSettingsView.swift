import SwiftUI

/// Configuración detallada de las alertas: permiso, tipos, umbrales (del rango de referencia), sensibilidad,
/// horas de silencio, consejos (T-25) y notificación de prueba.
struct AlertsSettingsView: View {
    let alerts: AlertsController

    var body: some View {
        Form {
            AlertPermissionSection(alerts: alerts)
            AlertKindsSection(alerts: alerts)
            AlertTipsSection(alerts: alerts)
            AlertThresholdsSection()
            AlertTimingSection(alerts: alerts)
            QuietHoursSection(alerts: alerts)
            AlertTestSection(alerts: alerts)
        }
        .navigationTitle(String(localized: "alerts.title", defaultValue: "Alertas"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
