import SwiftUI

/// Estado inicial: qué se enviará (período, tamaño, modelo, coste estimado) y el botón "Analizar".
struct ReportAnalysisIntroView: View {
    let outgoing: ReportAnalysisPreview?
    let modelLabel: String?
    let hasPricing: Bool
    let canAnalyze: Bool
    let analyze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Text(String(localized: "reports.analysis.intro.heading", defaultValue: "Qué se enviará"))
                .font(.headline)
                .foregroundStyle(Tokens.Studio.textPrimary)
            Text(String(localized: "reports.analysis.intro.privacy",
                        defaultValue: "Solo cifras del reporte: estadísticas, series y la hora, los carbohidratos o la duración de comidas y ejercicios. Sin nombres, notas, fotos ni identificadores."))
                .font(.subheadline)
                .foregroundStyle(Tokens.Studio.textSecondary)

            VStack(spacing: Tokens.Spacing.xs) {
                if let outgoing {
                    row(String(localized: "reports.analysis.intro.period", defaultValue: "Período"),
                        String(localized: "reports.analysis.intro.days", defaultValue: "\(outgoing.periodDays) días"))
                    row(String(localized: "reports.analysis.intro.size", defaultValue: "Tamaño"),
                        outgoing.payloadBytes.formatted(.byteCount(style: .file)))
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
