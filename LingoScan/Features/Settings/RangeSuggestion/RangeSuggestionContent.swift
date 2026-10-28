import SwiftUI

/// Secciones de una sugerencia lista: rango propuesto y origen, explicación, cada dato con su fuente y avisos.
struct RangeSuggestionContent: View {
    let suggestion: RangeSuggestion
    let currentLow: Int
    let currentHigh: Int
    /// Lo que se aplicará al aceptar (acotado a Ajustes) y si difiere de la sugerencia.
    let applied: (low: Int, high: Int)?
    let isAdjusted: Bool

    var body: some View {
        RangeSuggestionRangeSection(
            suggestion: suggestion, currentLow: currentLow, currentHigh: currentHigh, applied: applied, isAdjusted: isAdjusted)
        Section {
            Text(suggestion.explanation)
        } header: {
            Text(String(localized: "range.suggest.explanation", defaultValue: "Explicación"))
        }
        RangeSuggestionDataSection(suggestion: suggestion)
        if suggestion.healthNote != nil || suggestion.assistantNote != nil {
            Section {
                if let note = suggestion.healthNote {
                    Label(note, systemImage: "heart.text.clipboard")
                }
                if let note = suggestion.assistantNote {
                    Label(note, systemImage: "sparkles")
                        .foregroundStyle(Tokens.Palette.outOfRange)
                }
            } header: {
                Text(String(localized: "range.suggest.notes", defaultValue: "Avisos"))
            }
        }
    }
}
