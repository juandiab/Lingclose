import SwiftUI

/// Estado vacío dentro de una card: qué falta para ver el reporte (mínimos de `ReportThresholds`).
struct ReportEmptyState: View {
    let message: String
    var systemImage = "hourglass"

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ReportEmptyState(message: "La comparación necesita dos semanas con al menos 4 días de datos cada una.")
        .padding()
}
