import SwiftUI

/// Sección del análisis (un reporte) como card expandible: qué muestran los datos, por qué puede ocurrir, qué probar
/// y qué observar.
struct ReportAnalysisSectionCard: View {
    let section: ReportAnalysisReply.Section
    @State private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(section: ReportAnalysisReply.Section, startsExpanded: Bool) {
        self.section = section
        _isExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Button {
                withAnimation(Motion.animation(Motion.smooth, reduceMotion: reduceMotion)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Tokens.Spacing.xs) {
                    Text(section.title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Tokens.Studio.textPrimary)
                    Spacer(minLength: Tokens.Spacing.xs)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Tokens.Studio.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded
                ? String(localized: "reports.analysis.expanded", defaultValue: "Expandido")
                : String(localized: "reports.analysis.collapsed", defaultValue: "Contraído"))
            .accessibilityHint(String(localized: "reports.analysis.toggleHint", defaultValue: "Toca dos veces para expandir o contraer"))

            if isExpanded {
                block(String(localized: "reports.analysis.section.shows", defaultValue: "Qué muestran los datos"),
                      symbol: "chart.xyaxis.line", text: section.whatTheDataShows)
                block(String(localized: "reports.analysis.section.why", defaultValue: "Por qué puede ocurrir"),
                      symbol: "lightbulb", text: section.whyItMayHappen)
                block(String(localized: "reports.analysis.section.try", defaultValue: "Qué probar"),
                      symbol: "figure.walk", text: section.whatToTry)
                block(String(localized: "reports.analysis.section.watch", defaultValue: "Qué observar"),
                      symbol: "eye", text: section.whatToWatch)
            }
        }
        .padding(Tokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    @ViewBuilder
    private func block(_ title: String, symbol: String, text: String) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.Studio.textSecondary)
                Text(text)
                    .font(.body)
                    .foregroundStyle(Tokens.Studio.textPrimary)
            }
            .transition(.opacity)
        }
    }
}
