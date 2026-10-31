import SwiftUI

/// Ajustes › Personalización › Idioma: Sistema, Español, English o Português (Brasil). `String(localized:)` resuelve el
/// idioma al arrancar el proceso, así que aquí solo se guarda la preferencia y, si difiere del idioma de arranque, se
/// avisa al lado de que hay que reabrir la app.
struct LanguageRow: View {
    @State private var selection = LanguagePreference.current(defaults: .standard)
    private let launch = LaunchLanguage.process

    var body: some View {
        Picker(selection: $selection) {
            ForEach(LanguagePreference.allCases) { preference in
                Text(preference.displayName).tag(preference)
            }
        } label: {
            Label(String(localized: "settings.language", defaultValue: "Idioma"), systemImage: "globe")
        }
        .pickerStyle(.menu)
        .onChange(of: selection) { _, newValue in newValue.apply(defaults: .standard) }

        if launch.needsRelaunch(for: selection) {
            Label(
                String(localized: "settings.language.pending",
                       defaultValue: "Pendiente de reabrir la app: ciérrala desde el selector de apps y ábrela de nuevo. El sensor se reconecta solo."),
                systemImage: "arrow.clockwise"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    Form {
        LanguageRow()
    }
}
