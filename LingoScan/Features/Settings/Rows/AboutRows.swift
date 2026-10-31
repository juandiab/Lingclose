import SwiftUI

/// Ajustes › Acerca de: versión legible y enlace a "Información técnica" (compilación y base del fork).
struct AboutRows: View {
    let about: AboutInfo

    var body: some View {
        LabeledContent {
            Text(verbatim: about.version)
        } label: {
            SettingsRowTitle(title: String(localized: "settings.about.version", defaultValue: "Versión"), systemImage: "info.circle")
        }
        NavigationLink(value: SettingsRoute.technicalInfo) {
            SettingsRowTitle(title: String(localized: "settings.about.technical", defaultValue: "Información técnica"),
                             systemImage: "wrench.and.screwdriver")
        }
    }
}
