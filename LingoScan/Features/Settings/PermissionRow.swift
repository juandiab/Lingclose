import SwiftUI

/// Fila de permiso: texto e icono (el color nunca es la única señal).
struct PermissionRow: View {
    let title: String
    let state: PermissionState

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: Tokens.Spacing.xs)
            Label(text, systemImage: symbol)
                .foregroundStyle(state == .granted ? Tokens.Palette.inRange : .secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        switch state {
        case .granted: String(localized: "settings.permission.granted", defaultValue: "Concedido")
        case .denied: String(localized: "settings.permission.denied", defaultValue: "Denegado")
        case .notDetermined: String(localized: "settings.permission.notDetermined", defaultValue: "Sin decidir")
        case .unavailable: String(localized: "settings.permission.unavailable", defaultValue: "No disponible")
        }
    }

    private var symbol: String {
        switch state {
        case .granted: "checkmark.circle"
        case .denied: "xmark.circle"
        case .notDetermined: "questionmark.circle"
        case .unavailable: "minus.circle"
        }
    }
}
