import SwiftUI

/// Estado del permiso de notificaciones, con acceso a Ajustes de iOS si está denegado. El color va solo en el icono;
/// el texto usa los colores del sistema para mantener contraste AA en claro y en oscuro.
struct AlertPermissionSection: View {
    let alerts: AlertsController
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            switch alerts.permission {
            case .authorized:
                status(String(localized: "alerts.permission.on", defaultValue: "Notificaciones permitidas"),
                       systemImage: "checkmark.circle", tint: Tokens.Palette.inRange)
            case .notDetermined:
                Button(String(localized: "alerts.permission.ask", defaultValue: "Permitir notificaciones"), systemImage: "bell", action: requestPermission)
            case .denied:
                status(String(localized: "alerts.permission.denied", defaultValue: "Notificaciones desactivadas en iOS: las alertas no pueden llegar."),
                       systemImage: "bell.slash", tint: Tokens.Palette.outOfRange)
                Button(String(localized: "alerts.permission.open", defaultValue: "Abrir Ajustes de iOS"), systemImage: "gear", action: openSystemSettings)
            }
        } header: {
            Text(String(localized: "alerts.permission", defaultValue: "Permiso"))
        }
        .task { await alerts.refreshPermission() }
    }

    private func status(_ text: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }

    private func requestPermission() {
        Task { await alerts.enableAndRequestPermission() }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}
