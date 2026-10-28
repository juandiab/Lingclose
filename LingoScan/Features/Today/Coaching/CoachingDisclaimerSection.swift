import SwiftUI

/// Nota de no consejo médico de la hoja del asistente.
struct CoachingDisclaimerSection: View {
    var body: some View {
        Section {
            Label {
                Text(String(localized: "coaching.sheet.disclaimer", defaultValue: "Sugerencias de bienestar, no consejo médico ni un diagnóstico. Si tienes síntomas que persisten, consulta a un profesional de la salud. LingoScan no es un dispositivo médico."))
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
