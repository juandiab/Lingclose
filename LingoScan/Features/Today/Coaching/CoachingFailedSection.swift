import SwiftUI

/// Error claro, sin botón de reintentar (cada toque en la tarjeta es un intento).
struct CoachingFailedSection: View {
    let message: String

    var body: some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Tokens.Palette.error)
        } footer: {
            Text(String(localized: "coaching.sheet.noRetry", defaultValue: "No se reintentó para no cobrar dos veces. Cierra y vuelve a tocar \"Preguntar al asistente\" si quieres intentarlo de nuevo."))
        }
    }
}
