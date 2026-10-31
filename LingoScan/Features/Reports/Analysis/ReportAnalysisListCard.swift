import SwiftUI

/// Card con una lista de frases (salvedades o preguntas para explorar).
struct ReportAnalysisListCard: View {
    let title: String
    let symbol: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(Tokens.Studio.textPrimary)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xs) {
                    Text("•").foregroundStyle(Tokens.Studio.textTertiary).accessibilityHidden(true)
                    Text(item).foregroundStyle(Tokens.Studio.textPrimary)
                }
                .font(.subheadline)
            }
        }
        .padding(Tokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }
}
