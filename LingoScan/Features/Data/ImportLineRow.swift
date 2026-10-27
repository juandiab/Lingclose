import SwiftUI

/// Resumen de un paquete importado (`ImportSummary`), omitido o rechazado.
struct ImportLineRow: View {
    let line: ArchiveImportLine

    var body: some View {
        switch line.outcome {
        case .imported(let producer, let new, let updated, let identical, let conflicts):
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Label(String(localized: "data.import.ok", defaultValue: "Importado de \(producer)"), systemImage: "checkmark.circle")
                Text(String(localized: "data.import.counts", defaultValue: "\(new) nuevos, \(updated) actualizados, \(identical) idénticos, \(conflicts) conflictos"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .skipped(let producer):
            Label(String(localized: "data.import.skipped", defaultValue: "Ya conocido, sin cambios (\(producer))"), systemImage: "equal.circle")
                .foregroundStyle(.secondary)
        case .rejected(let name, let reason):
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Label(String(localized: "data.import.rejected", defaultValue: "Rechazado: \(name)"), systemImage: "xmark.octagon")
                    .foregroundStyle(Tokens.Palette.error)
                Text(verbatim: reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
