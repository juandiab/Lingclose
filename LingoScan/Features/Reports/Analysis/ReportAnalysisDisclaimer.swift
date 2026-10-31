import SwiftUI

/// Nota fija "guía, no diagnóstico", visible en todos los estados de la hoja.
struct ReportAnalysisDisclaimer: View {
    var body: some View {
        Label {
            Text(String(localized: "reports.analysis.disclaimer",
                        defaultValue: "Guía de bienestar generada por IA: no es un diagnóstico ni consejo médico."))
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.Spacing.sm)
        .padding(.vertical, Tokens.Spacing.xs)
        .background(.bar)
    }
}
