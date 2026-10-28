import SwiftUI

/// Estado del permiso de notificaciones, con acceso a Ajustes de iOS si está denegado.
struct AlertPermissionSection: View {
    let alerts: AlertsController
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            switch alerts.permission {
            case .authorized:
                Label(String(localized: "alerts.permission.on", defaultValue: "Notificaciones permitidas"), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .notDetermined:
                Button(String(localized: "alerts.permission.ask", defaultValue: "Permitir notificaciones"), systemImage: "bell", action: requestPermission)
            case .denied:
                Label(String(localized: "alerts.permission.denied", defaultValue: "Notificaciones desactivadas en iOS"), systemImage: "bell.slash")
                    .foregroundStyle(.orange)
                Button(String(localized: "alerts.permission.open", defaultValue: "Abrir Ajustes de iOS"), systemImage: "gear", action: openSystemSettings)
            }
        } header: {
            Text(String(localized: "alerts.permission", defaultValue: "Permiso"))
        }
        .task { await alerts.refreshPermission() }
    }

    private func requestPermission() {
        Task { await alerts.enableAndRequestPermission() }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}
