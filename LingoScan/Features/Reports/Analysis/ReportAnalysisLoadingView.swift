import SwiftUI

/// Mientras llega la respuesta: una sola petición en curso, que puede tardar hasta un minuto.
struct ReportAnalysisLoadingView: View {
    let modelLabel: String?

    var body: some View {
        VStack(spacing: Tokens.Spacing.xs) {
            ProgressView()
                .controlSize(.large)
            Text(String(localized: "reports.analysis.loading.title", defaultValue: "Analizando tu reporte…"))
                .font(.headline)
                .foregroundStyle(Tokens.Studio.textPrimary)
            Text(String(localized: "reports.analysis.loading.body",
                        defaultValue: "Una guía detallada puede tardar hasta un minuto. Puedes cerrar esta hoja: el resultado quedará en el historial."))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Tokens.Studio.textSecondary)
            if let modelLabel {
                Text(modelLabel)
                    .font(.caption)
                    .foregroundStyle(Tokens.Studio.textSecondary)
            }
        }
        .padding(Tokens.Spacing.md)
        .frame(maxWidth: .infinity)
        .studioCard()
        .accessibilityElement(children: .combine)
    }
}
