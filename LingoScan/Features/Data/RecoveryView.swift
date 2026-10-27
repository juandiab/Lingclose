import LingoCore
import SwiftUI
import UniformTypeIdentifiers

/// Archivo de recuperación cifrado (`RECUPERACION_V1.md`): frase, exportar, importar, conflictos y
/// acceso a "Conectar sensor activo" para una sesión importada.
struct RecoveryView: View {
    @State private var model: RecoveryViewModel
    @State private var importing = false

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
            if model.status.hasPassphrase {
                if model.status.passphraseRemembered {
                    Label(String(localized: "recovery.passphrase.inKeychain", defaultValue: "Frase guardada en el Llavero de este iPhone"), systemImage: "key.icloud.fill")
                } else {
                    Label(String(localized: "recovery.passphrase.inMemory", defaultValue: "Frase en memoria hasta cerrar la app"), systemImage: "key.fill")
                }
                Button(String(localized: "recovery.passphrase.forget", defaultValue: "Olvidar frase"), role: .destructive) {
                    Task { await model.forgetPassphrase() }
                }
            } else {
                SecureField(String(localized: "recovery.passphrase.field", defaultValue: "Frase (12 caracteres o más)"), text: $model.passphrase)
                    .textContentType(.password)
                    .submitLabel(.done)
                    .onSubmit { if passphraseIsLongEnough { Task { await model.usePassphrase() } } }
                Toggle(String(localized: "recovery.passphrase.remember", defaultValue: "Recordar en el Llavero"), isOn: $model.rememberPassphrase)
                Button(String(localized: "recovery.passphrase.use", defaultValue: "Usar frase")) {
                    Task { await model.usePassphrase() }
                }
                .disabled(!passphraseIsLongEnough)
            }
        } header: {
            Text(String(localized: "recovery.passphrase.title", defaultValue: "Frase de recuperación"))
        } footer: {
            Text(passphraseFooter)
        }
    }

    /// Mismo mínimo que el servicio, para que el botón no ofrezca lo que va a fallar.
    private var passphraseIsLongEnough: Bool {
        RecoveryPassphrase.normalized(model.passphrase).count >= RecoveryService.minimumPassphraseLength
    }

    private var passphraseFooter: String {
        if model.rememberPassphrase, !model.status.hasPassphrase {
            return String(localized: "recovery.passphrase.footer.remember", defaultValue: "Se guarda en el Llavero de este iPhone, protegida por el código y Face ID, y no se sube a iCloud. Anótala también fuera del teléfono: sin ella no hay recuperación.")
        }
        return String(localized: "recovery.passphrase.footer", defaultValue: "Se pide una vez por sesión de la app y no se guarda en el teléfono. Anótala fuera (gestor de contraseñas o papel): sin ella no hay recuperación.")
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
