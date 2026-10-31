import SwiftUI

/// Tabla compacta del perfil: hora, mediana y la mitad central (p25–p75) cada 2 horas.
struct HourlyProfileTable: View {
    let points: [HourlyProfilePoint]

    var body: some View {
        let rows = points.filter { ($0.minute - 15) % 120 == 0 }
        Grid(alignment: .leading, horizontalSpacing: Tokens.Spacing.md, verticalSpacing: Tokens.Spacing.xs) {
            GridRow {
                Text(String(localized: "reports.profile.table.hour", defaultValue: "Hora"))
                Text(String(localized: "reports.profile.table.median", defaultValue: "Mediana"))
                Text(String(localized: "reports.profile.table.middle", defaultValue: "Mitad central"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(rows) { point in
                GridRow {
                    Text(ReportFormat.clock(minute: point.minute - 15))
                    Text(verbatim: "\(Int(point.p50.rounded()))")
                        .fontWeight(.semibold)
                    Text(verbatim: "\(Int(point.p25.rounded()))–\(Int(point.p75.rounded()))")
                }
                .font(.subheadline)
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        }
    }
}
