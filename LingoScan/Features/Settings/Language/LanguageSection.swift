import SwiftUI

/// Ajustes › Idioma: Sistema, Español, English o Português (Brasil). `String(localized:)` resuelve el idioma al
/// arrancar el proceso, así que el cambio se aplica al volver a abrir la app; aquí solo se guarda la preferencia.
struct LanguageSection: View {
    /// Idioma con el que se abrió la pantalla; si la selección difiere, falta reabrir la app.
    @State private var initialSelection: LanguagePreference
    @State private var selection: LanguagePreference

    init() {
        let current = LanguagePreference.current(defaults: .standard)
        _initialSelection = State(initialValue: current)
        _selection = State(initialValue: current)
    }

    var body: some View {
        Section {
            Picker(String(localized: "settings.language", defaultValue: "Idioma"), selection: $selection) {
                ForEach(LanguagePreference.allCases) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .onChange(of: selection) { _, newValue in save(newValue) }

            if selection != initialSelection {
                Label(
                    String(localized: "settings.language.pending", defaultValue: "Pendiente de reabrir la app"),
                    systemImage: "arrow.clockwise"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "settings.language", defaultValue: "Idioma"))
        } footer: {
            Text(String(
                localized: "settings.language.footer",
                defaultValue: "Se aplica al volver a abrir la app. Cierra Lingclose desde el selector de apps y ábrela de nuevo; el sensor se reconecta solo."
            ))
        }
    }

    /// Guarda la preferencia; iOS la lee al próximo arranque del proceso.
    private func save(_ preference: LanguagePreference) {
        preference.apply(defaults: .standard)
    }
}

#Preview {
    Form {
        LanguageSection()
    }
}
