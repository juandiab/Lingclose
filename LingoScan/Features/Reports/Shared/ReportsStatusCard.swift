import SwiftUI

/// Antes del primer cálculo (cargando) o si falló la lectura de datos (con reintento).
struct ReportsStatusCard: View {
    let isFailure: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            if isFailure {
                Label(
                    String(localized: "reports.failure", defaultValue: "No se pudieron leer los datos guardados."),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(Tokens.Palette.error)
                Button(String(localized: "reports.retry", defaultValue: "Reintentar"), systemImage: "arrow.clockwise", action: onRetry)
                    .buttonStyle(.bordered)
            } else {
                HStack(spacing: Tokens.Spacing.sm) {
                    ProgressView()
                    Text(String(localized: "reports.loading.long", defaultValue: "Calculando reportes…"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .padding(Tokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reportSurface()
    }
}
