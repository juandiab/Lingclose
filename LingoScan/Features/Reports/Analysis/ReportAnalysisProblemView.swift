import SwiftUI

/// Respuesta descartada por el validador o error del análisis, con el motivo y la opción de volver a intentarlo
/// (una nueva petición, solo si la persona lo pide).
struct ReportAnalysisProblemView: View {
    let symbol: String
    let title: String
    let message: String
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(Tokens.Studio.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Tokens.Studio.textSecondary)
            Button(String(localized: "reports.analysis.retry", defaultValue: "Intentar de nuevo"), systemImage: "arrow.clockwise", action: retry)
                .buttonStyle(.bordered)
                .disabled(!canRetry)
            Text(String(localized: "reports.analysis.retry.note", defaultValue: "Volver a intentarlo hace otra llamada al proveedor."))
                .font(.footnote)
                .foregroundStyle(Tokens.Studio.textSecondary)
        }
        .padding(Tokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }
}
