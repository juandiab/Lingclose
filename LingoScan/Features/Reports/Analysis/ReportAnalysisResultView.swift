import SwiftUI

/// Resultado: panorama general, una card expandible por reporte, salvedades y preguntas para explorar.
struct ReportAnalysisResultView: View {
    let reply: ReportAnalysisReply

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(String(localized: "reports.analysis.overview", defaultValue: "Panorama general"))
                    .font(.headline)
                    .foregroundStyle(Tokens.Studio.textPrimary)
                Text(reply.overview)
                    .font(.body)
                    .foregroundStyle(Tokens.Studio.textPrimary)
            }
            .padding(Tokens.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioCard(tint: Tokens.Palette.inRange)

            ForEach(Array(reply.sections.enumerated()), id: \.offset) { index, section in
                ReportAnalysisSectionCard(section: section, startsExpanded: index == 0)
            }

            if !reply.caveats.isEmpty {
                ReportAnalysisListCard(
                    title: String(localized: "reports.analysis.caveats", defaultValue: "Ten en cuenta"),
                    symbol: "exclamationmark.circle", items: reply.caveats)
            }
            if !reply.questionsToExplore.isEmpty {
                ReportAnalysisListCard(
                    title: String(localized: "reports.analysis.questions", defaultValue: "Preguntas para explorar"),
                    symbol: "questionmark.bubble", items: reply.questionsToExplore)
            }
        }
    }
}
