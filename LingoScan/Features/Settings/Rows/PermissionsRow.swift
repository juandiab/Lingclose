import SwiftUI

/// Ajustes › Avanzado › Permisos: "Todo concedido" o cuántos faltan, y enlace a su pantalla.
struct PermissionsRow: View {
    let viewModel: SettingsViewModel

    var body: some View {
        NavigationLink(value: SettingsRoute.permissions) {
            LabeledContent {
                Text(summary)
            } label: {
                SettingsRowTitle(title: String(localized: "settings.permissions", defaultValue: "Permisos"),
                                 systemImage: "checkmark.shield")
            }
        }
    }

    private var summary: String {
        let missing = viewModel.missingPermissionCount
        guard missing > 0 else {
            return String(localized: "settings.permissions.allGranted", defaultValue: "Todo concedido")
        }
        return String(localized: "settings.permissions.missing", defaultValue: "Por revisar: \(missing)")
    }
}
