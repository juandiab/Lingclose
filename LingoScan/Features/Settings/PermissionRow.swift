import SwiftUI

/// Fila de permiso: texto e icono (el color nunca es la única señal; el texto conserva el color del sistema para
/// contraste AA) y, si no está concedido, una línea que dice qué hacer.
struct PermissionRow: View {
    let title: String
    let state: PermissionState
    var detail: String?

    static var healthDetail: String {
        String(localized: "settings.permission.health.detail", defaultValue: "Se pide en la pestaña Datos.")
    }

    var body: some View {
        // En fila mientras quepa; con texto grande, el estado baja debajo del título en vez de partir palabras.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(titleText)
                Spacer(minLength: Tokens.Spacing.xs)
                status.fixedSize()
            }
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Text(titleText)
                status
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Icono + texto en un `HStack` (no `Label`: dentro de una fila de `Form` el `Label` toma el estilo de fila y
    /// rompe el alto).
    private var status: some View {
        HStack(spacing: Tokens.Spacing.xxs) {
            Image(systemName: symbol)
                .foregroundStyle(state == .granted ? Tokens.Palette.inRange : .secondary)
            Text(text)
        }
    }

    /// Título y, si hay, la explicación en otra línea (U+2028, sin sangría de párrafo con texto grande).
    private var titleText: AttributedString {
        var result = AttributedString(title)
        guard let detail else { return result }
        var line = AttributedString("\u{2028}" + detail)
        line.font = .footnote
        line.foregroundColor = .secondary
        result.append(line)
        return result
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
