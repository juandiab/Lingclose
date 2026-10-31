import SwiftUI

/// Sin proveedor, clave y modelo: explica dónde configurarlos.
struct ReportAnalysisNotConfiguredView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Label(String(localized: "reports.analysis.notConfigured.title", defaultValue: "Falta configurar la IA"),
                  systemImage: "key")
                .font(.headline)
                .foregroundStyle(Tokens.Studio.textPrimary)
            Text(String(localized: "reports.analysis.notConfigured.body",
                        defaultValue: "Para analizar un reporte hace falta un proveedor, su clave y un modelo. Se configuran en Ajustes → Asistente de comidas y son los mismos del asistente de comidas. La clave se guarda solo en este iPhone."))
                .font(.subheadline)
                .foregroundStyle(Tokens.Studio.textSecondary)
        }
        .padding(Tokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }
}
