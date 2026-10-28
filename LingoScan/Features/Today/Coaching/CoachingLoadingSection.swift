import SwiftUI

/// "Preguntando al asistente…" con lo que se envía.
struct CoachingLoadingSection: View {
    var body: some View {
        Section {
            HStack(spacing: Tokens.Spacing.sm) {
                ProgressView()
                Text(String(localized: "coaching.sheet.loading", defaultValue: "Preguntando al asistente…"))
            }
        } footer: {
            Text(String(localized: "coaching.sheet.loading.footer", defaultValue: "Se envía solo el contexto de la alerta: tipo, valor, tendencia, hora, tiempo en rango, la última comida (nutrientes) y el último ejercicio. Nunca lecturas sueltas, nombres ni fotos."))
        }
    }
}
