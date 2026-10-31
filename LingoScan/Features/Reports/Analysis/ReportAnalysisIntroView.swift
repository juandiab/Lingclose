import SwiftUI

/// Estado inicial: qué se enviará (frase de privacidad según los interruptores, los tres interruptores del contexto
/// opcional, período, tamaño, modelo, coste estimado) y el botón "Analizar".
struct ReportAnalysisIntroView: View {
    let outgoing: ReportAnalysisPreview?
    let modelLabel: String?
    let hasPricing: Bool
    let canAnalyze: Bool
    @Binding var sharing: ReportAnalysisSharing
    let analyze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Text(String(localized: "reports.analysis.intro.heading", defaultValue: "Qué se enviará"))
                .font(.headline)
                .foregroundStyle(Tokens.Studio.textPrimary)
            Text(privacyText)
                .font(.subheadline)
                .foregroundStyle(Tokens.Studio.textSecondary)
                .contentTransition(.opacity)

            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportAnalysisSharingToggles(sharing: $sharing)
                Text(ReportAnalysisSharingOption.commonFooter)
                    .font(.footnote)
                    .foregroundStyle(Tokens.Studio.textSecondary)
                ForEach(gaps) { gap in
                    Label(gap.message, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Tokens.Studio.textSecondary)
                }
            }

            VStack(spacing: Tokens.Spacing.xs) {
                if let outgoing {
                    row(String(localized: "reports.analysis.intro.period", defaultValue: "Período"),
                        String(localized: "reports.analysis.intro.days", defaultValue: "\(outgoing.periodDays) días"))
                    row(String(localized: "reports.analysis.intro.size", defaultValue: "Tamaño"),
                        outgoing.payloadBytes.formatted(.byteCount(style: .file)))
                    if outgoing.contextBytes > 0 {
                        row(String(localized: "reports.analysis.intro.contextSize", defaultValue: "Incluye contexto opcional"),
                            outgoing.contextBytes.formatted(.byteCount(style: .file)))
                    }
                }
                if let modelLabel {
                    row(String(localized: "reports.analysis.intro.model", defaultValue: "Modelo"), modelLabel)
                }
                if let outgoing {
                    row(String(localized: "reports.analysis.intro.cost", defaultValue: "Coste estimado"), costText(outgoing))
                }
            }

            Button(action: analyze) {
                Label(String(localized: "reports.analysis.analyze", defaultValue: "Analizar"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canAnalyze || outgoing == nil)

            if !canAnalyze {
                Text(String(localized: "reports.analysis.intro.noData", defaultValue: "Este período no tiene lecturas que analizar."))
                    .font(.footnote)
                    .foregroundStyle(Tokens.Studio.textSecondary)
            }
            Text(String(localized: "reports.analysis.intro.oneCall",
                        defaultValue: "Cada toque en Analizar hace una sola llamada al proveedor, que puede cobrarte. No se reintenta sola."))
                .font(.footnote)
                .foregroundStyle(Tokens.Studio.textSecondary)
        }
        .padding(Tokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    /// La frase de siempre con todo apagado; con algo encendido, qué más va y por qué.
    private var privacyText: String {
        let enabled = sharing.enabled
        guard !enabled.isEmpty else {
            return String(localized: "reports.analysis.intro.privacy",
                          defaultValue: "Solo cifras del reporte: estadísticas, series y la hora, los carbohidratos o la duración de comidas y ejercicios. Sin nombres, notas, fotos ni identificadores.")
        }
        let extras = enabled.map(\.privacyItem).formatted(.list(type: .and))
        return String(localized: "reports.analysis.intro.privacyWithContext",
                      defaultValue: "Cifras del reporte (estadísticas, series y la hora, los carbohidratos o la duración de comidas y ejercicios) y, porque lo activaste, \(extras). Nunca fotos, notas, identificadores ni tu nombre.")
    }

    /// Bloques encendidos sin datos, solo si el cálculo corresponde a los interruptores que se ven.
    private var gaps: [ReportAnalysisContextGap] {
        guard let outgoing, outgoing.sharing == sharing else { return [] }
        return outgoing.gaps
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Tokens.Studio.textSecondary)
            Spacer(minLength: Tokens.Spacing.sm)
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(Tokens.Studio.textPrimary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func costText(_ outgoing: ReportAnalysisPreview) -> String {
        guard hasPricing, let usd = outgoing.estimate.usd else {
            return String(localized: "reports.analysis.intro.costUnpublished", defaultValue: "No publicado")
        }
        let amount = usd.formatted(.currency(code: "USD").precision(.fractionLength(3)))
        return String(localized: "reports.analysis.intro.costEstimate", defaultValue: "≈ \(amount) (estimado)")
    }
}
