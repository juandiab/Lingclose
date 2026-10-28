import SwiftUI

/// Resumen, sugerencias y precaución de una respuesta del asistente, con su origen.
struct CoachingReplySections: View {
    let answer: CoachingAnswer

    var body: some View {
        Section {
            Text(answer.reply.summary)
        } header: {
            Text(String(localized: "coaching.reply.summary", defaultValue: "Resumen"))
        } footer: {
            Text(answer.source)
        }
        if !answer.reply.suggestions.isEmpty {
            Section {
                ForEach(answer.reply.suggestions, id: \.self) { suggestion in
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                        Text(suggestion.title)
                            .font(.subheadline)
                            .bold()
                        Text(suggestion.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(String(localized: "coaching.reply.suggestions", defaultValue: "Sugerencias"))
            }
        }
        if let caution = answer.reply.caution {
            Section {
                Label(caution, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Tokens.Palette.outOfRange)
            }
        }
    }
}
