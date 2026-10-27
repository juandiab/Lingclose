import SwiftUI

/// Ajustes. Por ahora solo la identidad de app; en previsualización, un marcador.
struct SettingsView: View {
    /// `nil` en previsualización (`PreviewData`): no hay credenciales reales.
    let identity: IdentityImportModel?

    var body: some View {
        NavigationStack {
            Group {
                if let identity {
                    Form {
                        IdentitySection(model: identity)
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "settings.title", defaultValue: "Ajustes"),
                        systemImage: "gearshape",
                        description: Text(String(localized: "settings.placeholder", defaultValue: "Aquí ajustarás unidades, alarmas y permisos."))
                    )
                }
            }
            .navigationTitle(String(localized: "settings.title", defaultValue: "Ajustes"))
        }
    }
}

#Preview {
    SettingsView(identity: nil)
}
