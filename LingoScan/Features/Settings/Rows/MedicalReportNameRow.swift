import SwiftUI

/// Ajustes › Reporte médico › Nombre en los reportes (T-34): el nombre que lleva el PDF para el médico. Se guarda solo
/// en el dispositivo (`MedicalReportNameStore.key`, `UserDefaults`).
struct MedicalReportNameRow: View {
    @AppStorage(MedicalReportNameStore.key) private var name = ""

    var body: some View {
        let title = String(localized: "settings.medicalReport.name", defaultValue: "Nombre en los reportes")
        LabeledContent {
            // El título es la etiqueta de VoiceOver y Control por voz; "Opcional" es solo el texto de ayuda visual.
            TextField(title, text: $name,
                      prompt: Text(String(localized: "settings.medicalReport.name.placeholder", defaultValue: "Opcional")))
                .multilineTextAlignment(.trailing)
                .textContentType(.name)
                .autocorrectionDisabled()
                .submitLabel(.done)
        } label: {
            SettingsRowTitle(title: title, systemImage: "person.text.rectangle")
        }
        .onDisappear { name = MedicalReportNameStore.normalized(name) }
    }
}
