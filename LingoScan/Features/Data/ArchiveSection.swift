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
            if case .userFolder = viewModel.destination {
                Button(String(localized: "data.archive.useICloud", defaultValue: "Volver al iCloud de LingoScan"), systemImage: "icloud") {
                    Task { await viewModel.forgetFolder() }
                }
            }
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
            .disabled(viewModel.destination.url == nil || viewModel.isArchiveWorking)
            .sensoryFeedback(.success, trigger: viewModel.exportSummary) { _, new in new?.verified == true }
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
            Text(String(localized: "data.archive.footer", defaultValue: "Copia portable de tus datos. \"Disponible en iCloud\" solo aparece cuando el sistema confirma la subida."))
        }
        if !viewModel.visiblePackageList.isEmpty {
            Section(String(localized: "data.archive.recent", defaultValue: "Últimas copias")) {
                ForEach(viewModel.visiblePackageList) { package in
                    PackageRow(package: package)
                }
            }
        }
    }

    @ViewBuilder
    private var destinationRow: some View {
        switch viewModel.destination {
        case .userFolder(let url):
            LabeledContent(String(localized: "data.archive.folder", defaultValue: "Carpeta")) {
                Text(verbatim: url.lastPathComponent)
            }
        case .appICloudContainer:
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                LabeledContent(String(localized: "data.archive.folder", defaultValue: "Carpeta")) {
                    Text(String(localized: "data.archive.fallback", defaultValue: "iCloud de LingoScan"))
                }
                Text(String(localized: "data.archive.fallback.note", defaultValue: "Es el destino por omisión: aún no elegiste una carpeta."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Tokens.Palette.stale)
        }
    }

    private func exportRow(_ summary: ArchiveExportSummary) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            if summary.verified {
                Label(String(localized: "data.archive.export.ok", defaultValue: "Copia creada y verificada"), systemImage: "checkmark.seal")
            } else {
                Label(String(localized: "data.archive.export.unverified", defaultValue: "Copia creada, sin verificar"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Tokens.Palette.stale)
            }
            Text(String(localized: "data.archive.export.counts", defaultValue: "\(summary.readings) lecturas, \(summary.events) eventos del diario"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
