import SwiftUI

/// Etiqueta de un `Stepper` de Ajustes: el nombre y, debajo, el valor actual. Con texto grande el valor no se parte
/// al lado de los botones − / +, y VoiceOver lee nombre y valor juntos.
struct StepperValueLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text(title)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
