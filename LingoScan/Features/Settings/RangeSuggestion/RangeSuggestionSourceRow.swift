import SwiftUI

/// Un dato de la sugerencia con su valor (o "No disponible en Salud") y la fuente de la que salió.
struct RangeSuggestionSourceRow: View {
    let title: String
    let value: String?
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            LabeledContent(title) {
                Text(value ?? String(localized: "range.suggest.data.missing", defaultValue: "No disponible en Salud"))
                    .foregroundStyle(value == nil ? .secondary : .primary)
                    .monospacedDigit()
            }
            Text(String(localized: "range.suggest.source", defaultValue: "Fuente: \(source)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
