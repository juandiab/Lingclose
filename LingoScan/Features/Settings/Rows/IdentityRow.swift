import SwiftUI

/// Ajustes › Avanzado › Identidad del sensor: si hay identidad cargada y enlace a su pantalla. En la vista previa no
/// hay credenciales (`model == nil`) y la pantalla lo explica.
struct IdentityRow: View {
    let model: IdentityImportModel?

    var body: some View {
        NavigationLink(value: SettingsRoute.identity) {
            LabeledContent {
                Text(status)
            } label: {
                SettingsRowTitle(title: String(localized: "identity.header", defaultValue: "Identidad del sensor"),
                                 systemImage: "key")
            }
        }
        .task { await model?.refresh() }
    }

    private var status: String {
        guard let model else {
            return String(localized: "settings.preview.unavailable", defaultValue: "No disponible en la vista previa")
        }
        return model.summaries.isEmpty
            ? String(localized: "identity.state.missing", defaultValue: "Sin cargar")
            : String(localized: "identity.state.loaded", defaultValue: "Cargada")
    }
}
