import SwiftUI

/// Pantalla de alertas: interruptor general, permiso, qué avisar, umbrales (del rango de referencia), cuándo avisar,
/// horas de silencio, consejos (T-25) y notificación de prueba.
struct AlertsSettingsView: View {
    let alerts: AlertsController

    var body: some View {
        Form {
            AlertMasterSection(alerts: alerts)
            AlertPermissionSection(alerts: alerts)
            AlertKindsSection(alerts: alerts)
            AlertThresholdsSection()
            AlertTimingSection(alerts: alerts)
            QuietHoursSection(alerts: alerts)
            AlertTipsSection(alerts: alerts)
            AlertTestSection(alerts: alerts)
        }
        .navigationTitle(String(localized: "alerts.title", defaultValue: "Alertas"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
