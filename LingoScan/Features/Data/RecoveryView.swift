import LingoCore
import SwiftUI
import UniformTypeIdentifiers

/// Archivo de recuperación cifrado (`RECUPERACION_V1.md`): frase, exportar, importar, conflictos y
/// acceso a "Conectar sensor activo" para una sesión importada.
struct RecoveryView: View {
    @State private var model: RecoveryViewModel
    @State private var importing = false
    @State private var showingPassphraseSheet = false

    init(context: RecoveryContext = .resolve()) {
        _model = State(initialValue: RecoveryViewModel(context: context))
    }

    var body: some View {
        Form {
            passphraseSection
            exportSection
            importSection
            if let detail = model.importedSession {
                Section(String(localized: "recovery.imported.title", defaultValue: "Sesión importada")) {
                    NavigationLink {
                        ConnectActiveSensorView(detail: detail, connector: model.connector)
                    } label: {
                        LabeledContent(String(localized: "recovery.imported.state", defaultValue: "Estado"), value: detail.state.rawValue)
                    }
                }
            }
            if !model.status.conflicts.isEmpty || !model.status.historical.isEmpty {
                conflictsSection
            }
            if let message = model.message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "recovery.title", defaultValue: "Recuperación"))
        .disabled(model.isWorking)
        .overlay {
            if model.isWorking { ProgressView() }
        }
        .sheet(isPresented: $showingPassphraseSheet) {
            PassphraseEntrySheet(model: model)
                .presentationDetents([.large])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await model.importFile(url) }
            case .failure(let error): model.report(error)
            }
        }
        .task { await model.observe() }
        .task(id: model.status.lastExport) { await model.refreshShareFile() }
    }

    private var passphraseSection: some View {
        Section {
            passphraseStatusRow
            if model.status.hasPassphrase {
                Button(String(localized: "recovery.passphrase.forget", defaultValue: "Olvidar frase"), role: .destructive) {
                    Task { await model.forgetPassphrase() }
                }
            } else {
                Button(String(localized: "recovery.passphrase.enter", defaultValue: "Introducir frase…")) {
                    showingPassphraseSheet = true
                }
            }
        } header: {
            Text(String(localized: "recovery.passphrase.title", defaultValue: "Frase de recuperación"))
        } footer: {
            Text(String(localized: "recovery.passphrase.footer", defaultValue: "Se pide una vez por sesión de la app y no se guarda en el teléfono. Anótala fuera (gestor de contraseñas o papel): sin ella no hay recuperación."))
        }
    }

    @ViewBuilder
    private var passphraseStatusRow: some View {
        if !model.status.hasPassphrase {
            Label(String(localized: "recovery.passphrase.none", defaultValue: "Sin frase"), systemImage: "key.slash")
                .foregroundStyle(.secondary)
        } else if model.status.passphraseRemembered {
            Label(String(localized: "recovery.passphrase.inKeychain", defaultValue: "Frase guardada en el Llavero de este iPhone"), systemImage: "key.fill")
                .foregroundStyle(.green)
        } else {
            Label(String(localized: "recovery.passphrase.inMemory", defaultValue: "Frase en memoria hasta cerrar la app"), systemImage: "key.fill")
        }
    }

    private var exportSection: some View {
        Section {
            folderRow
            if !model.status.pendingSessionIDs.isEmpty {
                Label(String(localized: "recovery.pending", defaultValue: "Exportación pendiente: introduce la frase"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            lastExportRow
            shareRow
            if let confirmation = model.exportConfirmation {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    Label(String(localized: "recovery.export.confirmed", defaultValue: "Copia creada"), systemImage: "checkmark.seal")
                    Text(verbatim: confirmation.fileName)
                        .font(.footnote)
                        .textSelection(.enabled)
                    Text(String(localized: "recovery.export.at", defaultValue: "Hecha a las \(confirmation.at.formatted(date: .omitted, time: .standard))"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Toggle(String(localized: "recovery.includeMaterial", defaultValue: "Incluir material de identidad"), isOn: $model.includeMaterial)
            Button(String(localized: "recovery.exportNow", defaultValue: "Exportar ahora")) {
                Task { await model.exportNow() }
            }
            .disabled(!model.status.hasPassphrase)
            Button(String(localized: "recovery.astra.export", defaultValue: "Exportar sesión actual para Astra")) { Task { await model.exportForAstra() } }
                .disabled(!model.status.hasPassphrase)
            Text(String(localized: "recovery.astra.note", defaultValue: "Astra necesita la identidad original instalada o incluida en la copia cifrada. Una sesión preparada aún no permite recuperar un sensor activo."))
                .font(.footnote).foregroundStyle(.secondary)
            if let error = model.status.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(String(localized: "recovery.export.title", defaultValue: "Exportar"))
        }
    }

    private var folderRow: some View {
        let summary = model.destinationSummary
        return VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Label(summary.title, systemImage: summary.systemImage)
            switch model.status.exportFolderKind {
            case .documents:
                Text(String(localized: "recovery.folder.fallback", defaultValue: "Se guarda en Documentos de la app: aún no hay carpeta elegida. Compártelo a otro sitio tras exportar."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text(String(localized: "recovery.folder.unavailable", defaultValue: "La carpeta elegida ya no es accesible: se guarda en Documentos de la app. Elige la carpeta de nuevo en Datos."))
                    .font(.footnote)
                    .foregroundStyle(Tokens.Palette.stale)
            case .appICloudContainer:
                Text(String(localized: "recovery.folder.container.note", defaultValue: "Puedes cambiarla en Datos → Elegir carpeta…"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .chosen, .fixed:
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var lastExportRow: some View {
        if let last = model.status.lastExport {
            let newest = last.sessions.max { $0.sequence < $1.sequence }
            let date = last.at.formatted(date: .abbreviated, time: .shortened)
            if let newest {
                Text(String(localized: "recovery.last.detail", defaultValue: "Última copia: \(date), seq \(newest.sequence), \(newest.state.rawValue)"))
            } else {
                Text(String(localized: "recovery.last.dateOnly", defaultValue: "Última copia: \(date)"))
            }
        } else {
            Text(String(localized: "recovery.last.none", defaultValue: "Aún no hay copia"))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var shareRow: some View {
        switch model.shareFile {
        case .none:
            EmptyView()
        case .missing:
            Label(String(localized: "recovery.share.missing", defaultValue: "La última copia ya no está en la carpeta; exporta de nuevo"), systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Tokens.Palette.stale)
        case .ready(let url):
            ShareLink(item: url) {
                Label(String(localized: "recovery.share", defaultValue: "Compartir última copia"), systemImage: "square.and.arrow.up")
            }
        }
    }

    private var importSection: some View {
        Section {
            Button(String(localized: "recovery.import", defaultValue: "Importar desde archivo")) {
                importing = true
            }
            .disabled(!model.status.hasPassphrase)
        } header: {
            Text(String(localized: "recovery.import.title", defaultValue: "Importar"))
        } footer: {
            Text(String(localized: "recovery.import.footer", defaultValue: "Importar solo guarda los datos; no lee NFC ni conecta por Bluetooth. La sesión queda en pausa."))
        }
    }

    private var conflictsSection: some View {
        Section(String(localized: "recovery.conflicts.title", defaultValue: "Conflictos e intentos históricos")) {
            ForEach(model.status.conflicts) { conflict in
                VStack(alignment: .leading) {
                    Text(String(localized: "recovery.conflict.row", defaultValue: "Sesión \(String(conflict.sessionID.prefix(8))): secretos distintos"))
                    Text(conflict.fields.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "recovery.conflict.seqs", defaultValue: "local seq \(conflict.localSequence) · remota seq \(conflict.remoteSequence) · \(conflict.remoteExporter)"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(model.status.historical) { attempt in
                VStack(alignment: .leading) {
                    Text(String(localized: "recovery.historical.row", defaultValue: "Sesión \(String(attempt.sessionID.prefix(8))): otro intento"))
                    Text("\(String(attempt.attemptID.prefix(8))) · seq \(attempt.sequence) · \(attempt.state.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecoveryView()
    }
}
