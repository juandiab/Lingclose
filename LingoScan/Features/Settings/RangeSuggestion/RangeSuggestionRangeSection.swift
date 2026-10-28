import SwiftUI

/// Rango propuesto en grande, rango actual, origen y, si aplica, la propuesta estadística y el ajuste a Ajustes.
struct RangeSuggestionRangeSection: View {
    let suggestion: RangeSuggestion
    let currentLow: Int
    let currentHigh: Int
    let applied: (low: Int, high: Int)?
    let isAdjusted: Bool

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xs) {
                MetricText(value: suggestion.low, size: .large)
                Text(verbatim: "–")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                MetricText(value: suggestion.high, unit: "mg/dL", size: .large)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Tokens.Spacing.xs)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "range.suggest.range.a11y",
                                       defaultValue: "Rango sugerido de \(suggestion.low) a \(suggestion.high) miligramos por decilitro"))
            LabeledContent(String(localized: "range.suggest.current", defaultValue: "Rango actual"),
                           value: String(localized: "range.suggest.pair", defaultValue: "\(currentLow)–\(currentHigh) mg/dL"))
            LabeledContent(String(localized: "range.suggest.origin", defaultValue: "Origen"), value: originText)
            if suggestion.isAssistant, suggestion.differsFromStatistics {
                LabeledContent(String(localized: "range.suggest.statistical", defaultValue: "Solo estadística"),
                               value: String(localized: "range.suggest.pair", defaultValue: "\(suggestion.statisticalLow)–\(suggestion.statisticalHigh) mg/dL"))
            }
            if isAdjusted, let applied {
                Label(String(localized: "range.suggest.adjusted",
                             defaultValue: "Se aplicará \(applied.low)–\(applied.high) mg/dL, lo que Ajustes permite editar."),
                      systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "range.suggest.proposal", defaultValue: "Propuesta"))
        }
    }

    private var originText: String {
        switch suggestion.origin {
        case .statistics:
            String(localized: "range.suggest.origin.statistics", defaultValue: "Percentiles de tus lecturas")
        case .assistant(let provider, let modelName):
            String(localized: "range.suggest.origin.assistant", defaultValue: "Asistente: \(provider.displayName) · \(modelName)")
        }
    }
}
