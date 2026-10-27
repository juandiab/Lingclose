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
            if let last = model.status.lastExport {
                LabeledContent(String(localized: "recovery.last", defaultValue: "Última copia")) {
                    Text(last.at, format: .dateTime.day().month().hour().minute())
                }
                ForEach(last.sessions) { session in
                    LabeledContent(String(session.sessionID.prefix(8)), value: "seq \(session.sequence) · \(session.state.rawValue)")
                        .font(.footnote)
                }
                ShareLink(item: last.fileURL) {
                    Label(String(localized: "recovery.share", defaultValue: "Compartir última copia"), systemImage: "square.and.arrow.up")
                }
            }
            Toggle(String(localized: "recovery.includeMaterial", defaultValue: "Incluir material de identidad"), isOn: $model.includeMaterial)
            Button(String(localized: "recovery.exportNow", defaultValue: "Exportar ahora")) {
                Task { await model.exportNow() }
            }
            .disabled(!model.status.hasPassphrase)
            Button("Exportar sesión actual para Astra") { Task { await model.exportForAstra() } }
                .disabled(!model.status.hasPassphrase)
            Text("Astra necesita la identidad original instalada o incluida en la copia cifrada. Una sesión preparada aún no permite recuperar un sensor activo.")
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

    @ViewBuilder
    private var folderRow: some View {
        switch model.status.exportFolderKind {
        case .chosen, .fixed:
            LabeledContent(String(localized: "recovery.folder.label", defaultValue: "Carpeta"), value: model.status.exportFolderName)
        case .appICloudContainer:
            Label(String(localized: "recovery.folder.container", defaultValue: "Se guarda en el iCloud Drive de la app: aún no hay carpeta elegida en Datos."), systemImage: "folder.badge.questionmark")
                .font(.footnote)
        case .documents:
            Label(String(localized: "recovery.folder.fallback", defaultValue: "Se guarda en Documentos de la app: aún no hay carpeta elegida. Compártelo a otro sitio tras exportar."), systemImage: "folder.badge.questionmark")
                .font(.footnote)
        case .unavailable:
            Label(String(localized: "recovery.folder.unavailable", defaultValue: "La carpeta elegida ya no es accesible: se guarda en Documentos de la app. Elige la carpeta de nuevo en Datos."), systemImage: "folder.badge.minus")
                .font(.footnote)
                .foregroundStyle(.orange)
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
                    Text("local seq \(conflict.localSequence) · remota seq \(conflict.remoteSequence) · \(conflict.remoteExporter)")
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
