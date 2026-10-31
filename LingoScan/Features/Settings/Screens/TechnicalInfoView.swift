import SwiftUI

/// Ajustes › Acerca de › Información técnica: datos que solo hacen falta para depurar o informar de un fallo.
struct TechnicalInfoView: View {
    let about: AboutInfo

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "settings.about.version", defaultValue: "Versión"), value: about.version)
                LabeledContent(String(localized: "settings.about.build", defaultValue: "Compilación"), value: about.build)
                LabeledContent(String(localized: "settings.about.fork", defaultValue: "Base del fork")) {
                    Text(verbatim: about.forkBaseCommit)
                        .font(.body.monospaced())
                }
            } footer: {
                Text(String(localized: "settings.about.technical.footer", defaultValue: "La compilación identifica esta instalación. La base del fork es la versión de RoundWhiteDiscKit, la biblioteca que habla con el sensor, sobre la que se construye Lingclose."))
            }
        }
        .navigationTitle(String(localized: "settings.about.technical", defaultValue: "Información técnica"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TechnicalInfoView(about: AboutInfo(version: "0.4.4", build: "10"))
    }
}
