import SwiftUI

/// Pie de Hoy: aviso "no médico" en una línea y, con datos sintéticos, su rótulo.
struct TodayFooter: View {
    /// Rango de referencia de las estadísticas; `nil` sin datos (solo se muestra el rótulo sintético).
    let range: ClosedRange<Int>?
    let isSynthetic: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            if let range {
                Text(String(
                    localized: "today.footer.note",
                    defaultValue: "Informativo, no es un dispositivo médico · referencia \(range.lowerBound)–\(range.upperBound) mg/dL"
                ))
            }
            if isSynthetic {
                Label(
                    String(localized: "today.synthetic", defaultValue: "Datos de ejemplo (sintéticos). No son de un sensor real."),
                    systemImage: "testtube.2"
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
