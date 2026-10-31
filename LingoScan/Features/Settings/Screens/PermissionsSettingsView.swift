import SwiftUI

/// Ajustes › Avanzado › Permisos: Bluetooth, NFC y Apple Salud con lo que hacer si no están concedidos, y acceso a
/// Ajustes de iOS.
struct PermissionsSettingsView: View {
    let viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: String(localized: "settings.permission.bluetooth", defaultValue: "Bluetooth"),
                    state: viewModel.bluetooth,
                    detail: viewModel.bluetooth == .granted ? nil
                        : String(localized: "settings.permission.bluetooth.detail", defaultValue: "Sin Bluetooth no llegan lecturas del sensor. Actívalo en Ajustes de iOS."))
                PermissionRow(
                    title: String(localized: "settings.permission.nfc", defaultValue: "NFC"),
                    state: viewModel.nfcAvailable ? .granted : .unavailable,
                    detail: viewModel.nfcAvailable ? nil
                        : String(localized: "settings.permission.nfc.detail", defaultValue: "Este dispositivo no puede leer sensores al acercarlo (NFC). Las lecturas por Bluetooth siguen llegando."))
                PermissionRow(
                    title: String(localized: "settings.permission.health", defaultValue: "Apple Salud"),
                    state: viewModel.healthAuthorized ? .granted : .notDetermined,
                    detail: viewModel.healthAuthorized ? nil : PermissionRow.healthDetail)
            } footer: {
                Text(String(localized: "settings.permission.footer", defaultValue: "Bluetooth recibe las lecturas del sensor y NFC lo lee al acercar el iPhone. Si algo aparece denegado, cámbialo en Ajustes de iOS."))
            }
            Section {
                Button(String(localized: "settings.permission.open", defaultValue: "Abrir Ajustes de iOS"), systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
        .navigationTitle(String(localized: "settings.permissions", defaultValue: "Permisos"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refreshPermissions() }
    }
}
