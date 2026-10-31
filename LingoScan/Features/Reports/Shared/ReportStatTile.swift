import SwiftUI

/// Estadística compacta: etiqueta, valor `.rounded` con dígitos fijos, unidad y nota opcionales.
struct ReportStatTile: View {
    let title: String
    /// Valor ya formateado; `nil` se muestra como "--".
    let value: String?
    var unit: String?
    var note: String?
    /// Lectura de VoiceOver; sin ella, "<título>, <valor> <unidad>".
    var spoken: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xxs) {
                Text(verbatim: value ?? "--")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                if let unit, value != nil {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var spokenText: String {
        if let spoken { return spoken }
        guard let value else {
            return String(localized: "reports.tile.none.a11y", defaultValue: "\(title), sin datos")
        }
        let parts = [title, [value, unit].compactMap(\.self).joined(separator: " "), note].compactMap(\.self)
        return parts.joined(separator: ", ")
    }
}

#Preview {
    HStack {
        ReportStatTile(title: "Media", value: "118", unit: "mg/dL")
        ReportStatTile(title: "CV", value: "21 %", note: "variabilidad")
    }
    .padding()
}
