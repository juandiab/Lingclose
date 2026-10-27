import LingoCore
import SwiftUI

/// Un nutriente editable: valor numérico (coma o punto), "Desconocido" si no hay cifra y, si se corrigió a
/// mano, la marca "manual" con "Restablecer".
struct NutrientFieldRow: View {
    let field: NutrientField
    @Binding var text: String
    let isManual: Bool
    let isInvalid: Bool
    let onReset: () -> Void
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack {
                Text(field.title)
                Spacer(minLength: Tokens.Spacing.xs)
                TextField(
                    field.title,
                    text: $text,
                    prompt: Text(String(localized: "meal.field.unknown", defaultValue: "Desconocido"))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($isFocused)
                .frame(maxWidth: 140)
                Text(field.unit)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, alignment: .leading)
            }
            if isManual {
                HStack {
                    Text(String(localized: "meal.field.manual", defaultValue: "manual"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, Tokens.Spacing.xs)
                        .background(Color.accentColor.opacity(0.15), in: .capsule)
                    Button(String(localized: "meal.field.reset", defaultValue: "Restablecer")) {
                        onReset()
                        isFocused = false
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
            if isInvalid {
                Text(String(localized: "meal.field.invalid", defaultValue: "Escribe un número válido (0 o más)."))
                    .font(.caption)
                    .foregroundStyle(Tokens.Palette.error)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { onCommit() }
        }
        .accessibilityElement(children: .contain)
    }
}
