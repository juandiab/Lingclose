import SwiftUI

/// "Probar notificación" y aviso de que las alertas son informativas.
struct AlertTestSection: View {
    let alerts: AlertsController

    var body: some View {
        Section {
            Button(String(localized: "alerts.test", defaultValue: "Probar notificación"), systemImage: "bell.and.waves.left.and.right", action: sendTest)
            if let result = alerts.testResult {
                Text(result == .sent
                     ? String(localized: "alerts.test.sent", defaultValue: "Notificación de prueba enviada.")
                     : String(localized: "alerts.test.denied", defaultValue: "Sin permiso de notificaciones."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(String(localized: "alerts.disclaimer", defaultValue: "Las alertas son informativas y pueden retrasarse o no llegar (Bluetooth, batería, ajustes de iOS). LingoScan es un producto de bienestar, no un dispositivo médico; no tomes decisiones de salud solo con ellas."))
        }
    }

    private func sendTest() {
        Task { await alerts.sendTest() }
    }
}
