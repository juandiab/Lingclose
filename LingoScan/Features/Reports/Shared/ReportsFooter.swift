import SwiftUI

/// Pie de Reportes: aviso "no médico", rango de referencia y, con datos de ejemplo, su rótulo.
struct ReportsFooter: View {
    let range: ClosedRange<Int>
    let isSynthetic: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text(String(
                localized: "reports.footer.note",
                defaultValue: "Informativo, no es un dispositivo médico ni consejo médico · referencia \(range.lowerBound)–\(range.upperBound) mg/dL (Ajustes)"
            ))
            if isSynthetic {
                Label(
                    String(localized: "reports.synthetic", defaultValue: "Datos de ejemplo (sintéticos). No son de un sensor real."),
                    systemImage: "testtube.2"
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
