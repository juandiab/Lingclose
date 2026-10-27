import LingoCore
import SwiftUI

/// Tarjeta Archivo: carpeta, últimas copias con su estado de iCloud, exportar e importar.
struct ArchiveSection: View {
    let viewModel: DataViewModel
    let onChooseFolder: () -> Void
    let onImport: () -> Void

    var body: some View {
        Section {
            destinationRow
            Button(String(localized: "data.archive.choose", defaultValue: "Elegir carpeta…"), systemImage: "folder.badge.plus", action: onChooseFolder)
            Button(String(localized: "data.archive.useApp", defaultValue: "Usar la carpeta de la app"), systemImage: "icloud") {
                Task { await viewModel.forgetFolder() }
            }
            .disabled(!viewModel.canUseAppFolder)
            Button {
                Task { await viewModel.exportNow() }
            } label: {
                HStack {
                    Label(String(localized: "data.archive.export", defaultValue: "Exportar ahora"), systemImage: "square.and.arrow.up")
                    if viewModel.isArchiveWorking { ProgressView() }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(!viewModel.canExport)
            .sensoryFeedback(.success, trigger: viewModel.exportSummary) { _, new in new?.verified == true }
            if viewModel.isExportCoolingDown {
                Text(String(localized: "data.archive.export.wait", defaultValue: "Copia hecha. El botón vuelve en unos segundos para evitar duplicados."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let summary = viewModel.exportSummary {
                exportRow(summary)
            }
            Button(String(localized: "data.archive.import", defaultValue: "Importar paquete…"), systemImage: "square.and.arrow.down", action: onImport)
                .disabled(viewModel.isArchiveWorking)
            ForEach(viewModel.importLines) { line in
                ImportLineRow(line: line)
            }
            if let error = viewModel.archiveError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Tokens.Palette.error)
            }
        } header: {
            Text(String(localized: "data.archive.header", defaultValue: "Archivo .lingoscan"))
        } footer: {
            Text(String(localized: "data.archive.footer", defaultValue: "Copia portable de tus datos. \"Disponible en iCloud\" solo aparece cuando el sistema confirma la subida.")
                + "\n"
                + String(localized: "data.archive.retention", defaultValue: "Se conservan los últimos \(DataViewModel.retainedPackages) paquetes y uno por mes; los anteriores se borran."))
        }
        if !viewModel.visiblePackageList.isEmpty {
            Section(String(localized: "data.archive.recent", defaultValue: "Últimas copias")) {
                ForEach(viewModel.visiblePackageList) { package in
                    PackageRow(package: package)
                }
            }
        }
    }

    private var destinationRow: some View {
        let summary = viewModel.destinationSummary
        return VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Label(summary.title, systemImage: summary.systemImage)
                .foregroundStyle(summary == .none ? Tokens.Palette.stale : .primary)
            if case .unavailable(let reason) = viewModel.destination {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func exportRow(_ summary: ArchiveExportSummary) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            if summary.verified {
                Label(String(localized: "data.archive.export.ok", defaultValue: "Copia creada y verificada"), systemImage: "checkmark.seal")
            } else {
                Label(String(localized: "data.archive.export.unverified", defaultValue: "Copia creada, sin verificar"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Tokens.Palette.stale)
            }
            Text(verbatim: summary.packageName)
                .font(.footnote)
                .textSelection(.enabled)
            Text(String(localized: "data.archive.export.counts", defaultValue: "\(summary.readings) lecturas, \(summary.events) eventos del diario"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(String(localized: "data.archive.export.at", defaultValue: "Hecha a las \(summary.exportedAt.formatted(date: .omitted, time: .standard))"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if summary.removedByRetention > 0 {
                Text(String(localized: "data.archive.export.removed", defaultValue: "Se borraron \(summary.removedByRetention) paquetes antiguos por la retención"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
