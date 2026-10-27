import CryptoKit
import Foundation
import LingoCore
import RoundWhiteDiscKit

/// Archivo de recuperación cifrado (`LingoScan_Shared/RECUPERACION_V1.md` draft.4, T-19).
///
/// - Exporta: construye la carga §3.2 desde `PairingStatePersisting` (estado + Keychain) y la identidad
///   de app (solo hashes salvo `include_material`), la sella con `RecoveryCrypto` y la escribe de forma
///   atómica como `LingoScan-lingoscan-<UTC>-<id8>.lingoscan-recovery.json`. `sequence` crece en cada
///   exportación de la sesión.
/// - Importa: abre con la frase, valida el esquema, aplica `RecoveryMerge` contra el estado local y
///   guarda secretos vía `PairingStatePersisting`. La sesión queda marcada `imported` y en pausa: nunca
///   se conecta sola.
/// - La frase vive solo en memoria de este actor (una vez por ejecución de la app). Sin frase, las
///   exportaciones de transición quedan pendientes y se hacen al darla.
/// - Este actor no tiene referencia al NFC, al enlace BLE ni al coordinador: importar y validar no
///   puede activar ni conectar.
actor RecoveryService {
    static let producerTag = "lingoscan"
    static let ledgerFileName = "recovery-ledger.json"
    static let evidenceService = "com.otalvaro.lingoscan.recovery"
    static let evidenceAccount = "recovery-evidence"
    static let passphraseAccount = "recovery-passphrase"
    static let minimumPassphraseLength = 12

    private let pairingStore: any PairingStatePersisting
    private let credentials: (any PairingCredentialsProviding)?
    private let store: SQLiteStore?
    /// Carpeta fija (tests). `nil` resuelve el bookmark de la carpeta elegida en cada exportación.
    private let fixedExportDirectory: URL?
    private let bookmarks: any FolderBookmarkStoring
    private let fallbackContainer: @Sendable () async -> URL?
    private let ledgerURL: URL
    private let evidenceItem: KeychainItem?
    private let passphraseItem: (any SecretItemStoring)?
    private let iterations: UInt32
    private let appID: String
    private let appVersion: String
    private let now: @Sendable () -> Date

    private var passphrase: String?
    private var passphraseRemembered = false
    private var folder: ExportFolder
    private var ledger: Ledger
    private var evidence: Evidence
    private var lastError: String?
    private var observers: [UUID: AsyncStream<Status>.Continuation] = [:]

    /// - Parameters:
    ///   - exportDirectory: carpeta fija (tests). Con `nil`, cada exportación resuelve el mismo bookmark que el
    ///     archivo `.lingoscan` (`bookmarks`); sin carpeta elegida cae al contenedor iCloud propio y, si no hay
    ///     iCloud, a `Documents/`. `Status.exportFolder` lo dice en la UI.
    ///   - passphraseItem: ítem del Keychain donde se guarda la frase solo si Juampa marca "recordar"
    ///     (`AfterFirstUnlockThisDeviceOnly`, sin iCloud). `nil` la deja solo en memoria (tests).
    ///   - stateDirectory: donde vive `recovery-ledger.json` (sin secretos).
    ///   - evidenceItem: ítem de Keychain para las copias íntegras de conflictos e intentos históricos
    ///     (contienen secretos). `nil` las deja solo en memoria (tests).
    ///   - iterations: PBKDF2; los tests usan menos para ir rápido.
    init(
        pairingStore: any PairingStatePersisting,
        credentials: (any PairingCredentialsProviding)?,
        store: SQLiteStore?,
        exportDirectory: URL? = nil,
        bookmarks: any FolderBookmarkStoring = UserDefaultsFolderBookmarkStore(),
        fallbackContainer: @escaping @Sendable () async -> URL? = ArchiveService.iCloudContainerDocuments,
        stateDirectory: URL = .applicationSupportDirectory,
        evidenceItem: KeychainItem? = KeychainItem(service: RecoveryService.evidenceService, account: RecoveryService.evidenceAccount),
        passphraseItem: (any SecretItemStoring)? = KeychainItem(service: RecoveryService.evidenceService, account: RecoveryService.passphraseAccount),
        iterations: UInt32 = RecoveryKDF.defaultIterations,
        appID: String = SensorSessionCoordinator.appID,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.pairingStore = pairingStore
        self.credentials = credentials
        self.store = store
        self.fixedExportDirectory = exportDirectory
        self.bookmarks = bookmarks
        self.fallbackContainer = fallbackContainer
        self.folder = exportDirectory.map { ExportFolder(url: $0, kind: .fixed) } ?? ExportFolder(url: .documentsDirectory, kind: .documents)
        self.ledgerURL = stateDirectory.appending(path: Self.ledgerFileName)
        self.evidenceItem = evidenceItem
        self.passphraseItem = passphraseItem
        self.iterations = iterations
        self.appID = appID
        self.appVersion = appVersion
        self.now = now
        self.ledger = (try? Data(contentsOf: stateDirectory.appending(path: Self.ledgerFileName)))
            .flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) } ?? Ledger()
        self.evidence = (try? evidenceItem?.read())
            .flatMap { $0 }
            .flatMap { try? JSONDecoder().decode(Evidence.self, from: $0) } ?? Evidence()
        // Frase recordada en el Keychain (opcional): disponible desde el arranque, sin pedirla.
        if let data = try? passphraseItem?.read(), let remembered = String(data: data, encoding: .utf8),
           RecoveryPassphrase.normalized(remembered).count >= Self.minimumPassphraseLength {
            passphrase = remembered
            passphraseRemembered = true
        }
    }

    /// Resuelve la carpeta de exportación y hace las exportaciones pendientes si hay frase (recordada o dada).
    /// Lo llama `installRecovery()` al arrancar y la pantalla de Recuperación al abrirse.
    func start() async {
        await refreshFolder()
        if passphrase != nil { await flushPending() }
        publish()
    }

    // MARK: - Frase (memoria y, si se pide, Keychain)

    var hasPassphrase: Bool { passphrase != nil }

    /// Guarda la frase en memoria (y en el Keychain si `remember`) y hace las exportaciones pendientes.
    func setPassphrase(_ text: String, remember: Bool = false) async throws {
        guard RecoveryPassphrase.normalized(text).count >= Self.minimumPassphraseLength else {
            throw RecoveryServiceError.passphraseTooShort(minimum: Self.minimumPassphraseLength)
        }
        passphrase = text
        if remember, let passphraseItem {
            do {
                try passphraseItem.save(Data(text.utf8))
                passphraseRemembered = true
            } catch {
                passphraseRemembered = false
                lastError = String(localized: "recovery.error.remember", defaultValue: "No se pudo guardar la frase en el Llavero; queda solo en memoria")
            }
        } else {
            try? passphraseItem?.delete()
            passphraseRemembered = false
        }
        await flushPending()
        publish()
    }

    /// Olvida la frase en memoria y borra la copia del Keychain si la había.
    func forgetPassphrase() {
        passphrase = nil
        passphraseRemembered = false
        try? passphraseItem?.delete()
        publish()
    }

    // MARK: - Carpeta de exportación

    /// Carpeta elegida (bookmark) > carpeta fija (tests) > contenedor iCloud propio > Documents.
    func refreshFolder() async {
        if let fixedExportDirectory {
            folder = ExportFolder(url: fixedExportDirectory, kind: .fixed)
            return
        }
        if let data = bookmarks.load() {
            if let resolved = try? FolderBookmark.resolve(data) {
                if let fresh = resolved.refreshedData { bookmarks.save(fresh) }
                folder = ExportFolder(url: resolved.url, kind: .chosen)
                return
            }
            folder = ExportFolder(url: .documentsDirectory, kind: .unavailable)
            return
        }
        if let container = await fallbackContainer() {
            folder = ExportFolder(url: container, kind: .appICloudContainer)
            return
        }
        folder = ExportFolder(url: .documentsDirectory, kind: .documents)
    }

    // MARK: - Exportación

    /// Hook de `RecoveryExportHook`: tras persistir `prepared`, `response_saved` o `authenticated`.
    func checkpoint(_ record: ActivationRecord) async {
        guard passphrase != nil else {
            if !ledger.pendingSessionIDs.contains(record.sessionID) { ledger.pendingSessionIDs.append(record.sessionID) }
            saveLedger()
            await log(.warning, "exportación de recuperación pendiente (sin frase en memoria): sesión \(public: record.sessionID), estado \(public: record.state.rawValue)")
            publish()
            return
        }
        do {
            _ = try await export(sessionIDs: [record.sessionID], includeMaterial: false, trigger: record.state.rawValue)
        } catch {
            if !ledger.pendingSessionIDs.contains(record.sessionID) { ledger.pendingSessionIDs.append(record.sessionID) }
            saveLedger()
            lastError = String(describing: error)
            await log(.error, "exportación de recuperación fallida en \(public: record.state.rawValue): \(public: String(describing: type(of: error)))")
            publish()
        }
    }

    /// Exportación a petición: todas las sesiones conocidas (actual, exportadas o importadas).
    @discardableResult
    func exportNow(includeMaterial: Bool = false) async throws -> ExportRecord {
        var ids = Set(ledger.exportSequences.keys).union(ledger.imported.keys)
        if let current = try await pairingStore.currentSessionID() { ids.insert(current) }
        var existing: [String] = []
        for id in ids.sorted() where try await pairingStore.loadState(sessionID: id) != nil { existing.append(id) }
        guard !existing.isEmpty else { throw RecoveryServiceError.nothingToExport }
        do {
            return try await export(sessionIDs: existing, includeMaterial: includeMaterial, trigger: "manual")
        } catch {
            lastError = String(describing: error)
            publish()
            throw error
        }
    }

    /// Export exactly one complete current session for Astra, without contacting a sensor.
    func exportCurrentForAstra(includeMaterial: Bool = false) async throws -> ExportRecord {
        guard let id = try await pairingStore.currentSessionID(),
              let (session, receiver, state) = try await localSnapshot(sessionID: id) else { throw RecoveryServiceError.nothingToExport }
        guard let rawPatch = session.patchInfoHex.flatMap({ Data(lowercaseHex: $0) }) else { throw RecoveryServiceError.missingPatchInfo }
        guard let patch = try? Libre3NFCPatchInfo(raw: rawPatch), patch.productType == 9, patch.securityVersion == 3,
              patch.serialNumber == session.sensorSerial, patch.wearDurationMinutes > 0, patch.warmupMinutes > 0,
              patch.warmupMinutes < patch.wearDurationMinutes,
              [.responseSaved, .authenticated].contains(session.activation.state), receiver != 0,
              session.activation.receiverIDUsed == receiver,
              let responseData = session.activation.responseHex.flatMap({ Data(lowercaseHex: $0) }),
              let response = try? Libre3NFCActivationResponse(raw: responseData),
              response.blePIN.lowercaseHex == session.ble.pinHex, response.bleAddressDisplay == session.ble.address,
              response.bleAddressDisplay != "00:00:00:00:00:00", response.bleAddressDisplay != "FF:FF:FF:FF:FF:FF",
              let epoch = session.activation.activationTimeEpochS, epoch > 0,
              epoch <= Int64(now().timeIntervalSince1970 + 300),
              Int64(response.activationTimeRaw.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }) == epoch,
              session.firmwareHex != nil else { throw RecoveryServiceError.incompleteForAstra }
        let identity = try await appIdentity(for: state, includeMaterial: includeMaterial)
        guard identity.productTypes.contains(9), identity.securityVersions.contains(3), identity.certificateSHA256 != nil,
              identity.patchSigningKeySHA256 != nil else { throw RecoveryServiceError.identityUnavailable }
        return try await export(sessionIDs: [id], includeMaterial: includeMaterial, trigger: "astra")
    }

    private func flushPending() async {
        let pending = ledger.pendingSessionIDs
        guard !pending.isEmpty else { return }
        var ids: [String] = []
        for id in pending where (try? await pairingStore.loadState(sessionID: id)) != nil { ids.append(id) }
        guard !ids.isEmpty else {
            ledger.pendingSessionIDs = []
            saveLedger()
            return
        }
        do {
            _ = try await export(sessionIDs: ids, includeMaterial: false, trigger: "pendiente")
        } catch {
            lastError = String(describing: error)
            await log(.error, "exportación pendiente fallida: \(public: String(describing: type(of: error)))")
        }
    }

    private func export(sessionIDs: [String], includeMaterial: Bool, trigger: String) async throws -> ExportRecord {
        guard let passphrase else { throw RecoveryServiceError.passphraseRequired }
        var sessions: [RecoveryPayload.Session] = []
        var receiverIDs: [UInt32] = []
        var firstState: PairingState?
        for id in sessionIDs {
            guard let (snapshot, receiverID, state) = try await localSnapshot(sessionID: id) else {
                throw RecoveryServiceError.sessionIncomplete(id)
            }
            var session = snapshot
            session.sequence = (ledger.exportSequences[id] ?? 0) + 1
            sessions.append(session)
            receiverIDs.append(receiverID)
            if firstState == nil { firstState = state }
        }
        guard let firstState, let receiverID = receiverIDs.first else { throw RecoveryServiceError.nothingToExport }

        let created = now()
        let createdUTC = RecoveryPayload.utcString(created)
        let payload = RecoveryPayload(
            exportedAtUTC: createdUTC,
            exportedByAppID: appID,
            receiverID: receiverID,
            receiverIDOrigin: ledger.imported[sessionIDs[0]] == nil ? .generated : .imported,
            appIdentity: try await appIdentity(for: firstState, includeMaterial: includeMaterial),
            sessions: sessions
        )
        try payload.validate()

        let archiveID = UUID().uuidString.lowercased()
        let envelope = try RecoveryCrypto.seal(
            plaintext: try payload.encoded(), passphrase: passphrase, archiveID: archiveID, createdAtUTC: createdUTC,
            producer: .init(appID: appID, producerTag: Self.producerTag, appVersion: appVersion), iterations: iterations
        )
        let fileName = Self.fileName(createdUTC: createdUTC, archiveID: archiveID)
        await refreshFolder()
        let exportDirectory = folder.url
        let url = exportDirectory.appending(path: fileName)
        let data = try envelope.encoded()
        try SecurityScopedAccess.run(exportDirectory) {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }

        for (id, session) in zip(sessionIDs, sessions) {
            ledger.exportSequences[id] = session.sequence
            ledger.activeExporters[id] = appID
        }
        ledger.pendingSessionIDs.removeAll { sessionIDs.contains($0) }
        let record = ExportRecord(
            fileName: fileName, fileURL: url, at: created, trigger: trigger,
            sessions: zip(sessionIDs, sessions).map { ExportedSession(sessionID: $0, sequence: $1.sequence, state: $1.activation.state) }
        )
        ledger.lastExport = record
        saveLedger()
        lastError = nil
        await log(.info, "recuperación exportada (\(public: trigger)): \(public: fileName), \(sessions.count) sesión(es), sequence \(public: sessions.map { String($0.sequence) }.joined(separator: ","))")
        publish()
        return record
    }

    /// `LingoScan-<producer_tag>-<YYYYMMDDTHHMMSSZ>-<archive_id_8>.lingoscan-recovery.json` (§3).
    static func fileName(createdUTC: String, archiveID: String) -> String {
        let compact = createdUTC.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        return "LingoScan-\(producerTag)-\(compact)-\(archiveID.prefix(8)).lingoscan-recovery.json"
    }

    // MARK: - Importación

    /// Importa un archivo elegido por el usuario. No ejecuta NFC ni BLE.
    @discardableResult
    func importFile(at url: URL) async throws -> ImportReport {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw RecoveryServiceError.unreadableFile }
        return try await importData(data)
    }

    @discardableResult
    func importData(_ data: Data) async throws -> ImportReport {
        guard let passphrase else { throw RecoveryServiceError.passphraseRequired }
        do {
            let envelope = try RecoveryEnvelope.decode(data)
            let plaintext = try RecoveryCrypto.open(envelope, passphrase: passphrase)
            let payload = try RecoveryPayload.decode(plaintext)
            let report = try await merge(payload, archiveID: envelope.archiveID)
            lastError = nil
            publish()
            return report
        } catch {
            lastError = String(describing: error)
            await log(.warning, "importación de recuperación rechazada: \(public: String(describing: type(of: error)))")
            publish()
            throw error
        }
    }

    private func merge(_ payload: RecoveryPayload, archiveID: String) async throws -> ImportReport {
        var state = try await localMergeState(for: payload)
        state.conflicts = evidence.conflicts
        state.historical = evidence.historical
        let (merged, decisions) = RecoveryMerge.apply(payload, to: state)
        let importedAt = now()

        for (decision, remote) in zip(decisions, payload.sessions) {
            switch decision {
            case .importedNew(let id), .replacedByRemote(let id, _, _):
                guard let session = merged.sessions[id] else { continue }
                try await persistImported(session, canonicalID: id, payload: payload, archiveID: archiveID, at: importedAt)
            case .secretConflict(let id, let fields):
                if let conflict = merged.conflicts.last(where: { $0.sessionID == id && $0.remote == remote }) {
                    evidence.conflicts.append(conflict)
                    ledger.conflicts.append(ConflictSummary(
                        sessionID: id, attemptID: remote.attemptID, fields: fields, localSequence: conflict.local.sequence,
                        remoteSequence: remote.sequence, remoteExporter: payload.exportedByAppID, archiveID: archiveID, at: importedAt
                    ))
                }
                await log(.warning, "recuperación: conflicto de secretos en sesión \(public: id) (\(public: fields.joined(separator: ","))); se conserva la local")
            case .historicalAttempt(let id, let attemptID):
                if let attempt = merged.historical.last(where: { $0.sessionID == id && $0.session == remote }) {
                    evidence.historical.append(attempt)
                }
                ledger.historical.append(HistoricalSummary(
                    sessionID: id, attemptID: attemptID, sequence: remote.sequence, state: remote.activation.state,
                    remoteExporter: payload.exportedByAppID, archiveID: archiveID, at: importedAt
                ))
                await log(.warning, "recuperación: otro intento \(public: attemptID) de la sesión \(public: id) guardado como histórico")
            case .keptLocal, .duplicateIgnored:
                break
            }
        }
        for (alias, canonical) in merged.aliases { ledger.aliases[alias] = canonical }
        saveEvidence()
        saveLedger()
        return ImportReport(archiveID: archiveID, exporter: payload.exportedByAppID, decisions: decisions)
    }

    /// Estado local para la fusión: la sesión con el mismo id, su alias y las conocidas (equivalencia ±120 s).
    private func localMergeState(for payload: RecoveryPayload) async throws -> RecoveryMergeState {
        var ids = Set(ledger.exportSequences.keys).union(ledger.imported.keys)
        if let current = try await pairingStore.currentSessionID() { ids.insert(current) }
        for remote in payload.sessions {
            ids.insert(remote.sessionID)
            if let canonical = ledger.aliases[remote.sessionID] { ids.insert(canonical) }
        }
        var state = RecoveryMergeState(aliases: ledger.aliases)
        for id in ids.sorted() {
            guard let (snapshot, _, _) = try await localSnapshot(sessionID: id) else { continue }
            var session = snapshot
            session.sequence = ledger.exportSequences[id] ?? 0
            state.sessions[id] = session
            state.exporters[id] = ledger.activeExporters[id] ?? appID
        }
        return state
    }

    private func persistImported(
        _ session: RecoveryPayload.Session, canonicalID id: String, payload: RecoveryPayload, archiveID: String, at date: Date
    ) async throws {
        let existing = try await pairingStore.loadState(sessionID: id)
        let activation = try Self.activationRecord(sessionID: id, session: session, updatedAt: date)
        var state: PairingState
        if var existing {
            existing.activation = activation
            state = existing
        } else {
            state = PairingState(activation: activation, profile: Self.profile(for: session, identity: payload.appIdentity))
        }
        if let epoch = session.activation.activationTimeEpochS { state.activationTimeEpochS = epoch }
        if let lc = session.auth.lastLifeCount { state.lastLifeCount = lc }
        state.identityLabel = payload.appIdentity.label
        state.authFailurePhase = nil
        state.authFailureSummary = nil
        // Importar nunca conecta: queda en pausa hasta "Conectar sensor activo".
        state.collectorPaused = true

        // `nil` no borra lo que ya hubiera en el Keychain (un null remoto no es un dato).
        var secrets = PairingSecrets()
        secrets.receiverID = session.activation.receiverIDUsed ?? payload.receiverID
        secrets.pin = session.ble.pinHex.flatMap { Data(lowercaseHex: $0) }
        secrets.kAuth = session.auth.kAuthHex.flatMap { Data(lowercaseHex: $0) }
        secrets.bleAddress = session.ble.address
        secrets.activationResponse = session.activation.responseHex.flatMap { Data(lowercaseHex: $0) }
        secrets.serial = session.sensorSerial
        secrets.patchInfoRaw = session.patchInfoHex.flatMap { Data(lowercaseHex: $0) }
        try await pairingStore.saveSecrets(secrets, sessionID: id)
        try await pairingStore.saveState(state)

        ledger.imported[id] = ImportRecord(
            sessionID: id, archiveID: archiveID, fromAppID: payload.exportedByAppID, attemptID: session.attemptID,
            state: session.activation.state, sequence: session.sequence, sensorSerialHash: session.sensorSerialHash, importedAt: date
        )
        ledger.exportSequences[id] = max(ledger.exportSequences[id] ?? 0, session.sequence)
        ledger.activeExporters[id] = payload.exportedByAppID
        try await upsertSessionRecord(session, id: id, existing: existing != nil, payload: payload, archiveID: archiveID, state: state)
        await log(.info, "recuperación importada: sesión \(public: id), intento \(public: session.attemptID), sequence \(session.sequence), estado \(public: session.activation.state.rawValue); en pausa")
    }

    /// `ActivationRecord` no expone un init con estado arbitrario (solo `prepared` y `advancing`);
    /// se reconstruye por su forma persistida, la misma que lee `PairingStateStore`.
    static func activationRecord(sessionID: String, session: RecoveryPayload.Session, updatedAt: Date) throws -> ActivationRecord {
        var object: [String: Any] = [
            "session_id": sessionID,
            "attempt_id": session.attemptID,
            "activation_state": session.activation.state.rawValue,
            "sequence": session.sequence,
            "updated_at": ISO8601DateFormatter().string(from: updatedAt),
        ]
        if session.activation.state == .failed, let error = session.activation.error { object["failure_reason"] = error }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ActivationRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func profile(for session: RecoveryPayload.Session, identity: RecoveryPayload.AppIdentity) -> SensorProfile {
        let productType = UInt8(clamping: session.productType ?? Int(identity.productTypes.first ?? 0))
        let securityVersion = UInt16(clamping: session.securityVersion ?? Int(identity.securityVersions.first ?? 0))
        let family: RWDKSensorFamily = RWDKSensorFamily.allCases.first { $0.productType == productType } ?? .unknown
        return SensorProfile(
            family: family, productType: productType, securityVersion: securityVersion, serial: session.sensorSerial ?? "",
            warmupMinutes: SensorLifecycle.warmupDurationMinutes(rawMinutes: 0, family: family),
            wearMinutes: SensorLifecycle.wearDurationMinutes(rawMinutes: 0, family: family),
            firmwareHex: session.firmwareHex ?? "",
            // Estado del parche desconocido: nunca 0x01 ("sin activar"), así no hay ticket posible.
            stateByte: 0
        )
    }

    private func upsertSessionRecord(
        _ session: RecoveryPayload.Session, id: String, existing: Bool, payload: RecoveryPayload, archiveID: String, state: PairingState
    ) async throws {
        guard let store else { return }
        if var record = try await store.session(byID: id) {
            record.activationState = session.activation.state
            if let lc = session.auth.lastLifeCount { record.lastLifeCount = lc }
            record.revision += 1
            try await store.upsertSession(record)
            return
        }
        // Sin tiempo de activación conocido no se crea la fila: inventarlo rompería la equivalencia ±120 s.
        guard let epoch = session.activation.activationTimeEpochS else { return }
        let family = CoreSensorFamily(rawValue: state.family.rawValue) ?? .unknown
        try await store.upsertSession(SensorSessionRecord(
            sessionID: id, sensorFamily: family, productType: Int(state.productType), securityVersion: Int(state.securityVersion),
            sensorSerialHash: session.sensorSerialHash, synthetic: false,
            sensorSerialRedacted: session.sensorSerial.map(Redactor.serial), firmwareHex: session.firmwareHex,
            warmupMinutes: state.warmupMinutes, wearMinutes: state.wearMinutes, activationTimeEpochS: epoch,
            activationTimeSource: .imported, activatedByAppID: payload.exportedByAppID, activationSource: .imported,
            activationState: session.activation.state, receiverIDPresent: true, lastLifeCount: session.auth.lastLifeCount,
            importedFrom: ImportedFrom(appID: payload.exportedByAppID, archiveID: archiveID)
        ))
    }

    // MARK: - Carga desde el estado local

    /// Sesión §3.2 desde el estado local (sin `sequence`, que la pone quien llama), su Receiver ID y estado.
    private func localSnapshot(sessionID id: String) async throws -> (RecoveryPayload.Session, UInt32, PairingState)? {
        guard let state = try await pairingStore.loadState(sessionID: id) else { return nil }
        let secrets = try await pairingStore.loadSecrets(sessionID: id)
        guard let receiverID = secrets.receiverID else { return nil }
        let hash: String
        if let serial = secrets.serial, !serial.isEmpty {
            hash = Data(SHA256.hash(data: Data(("lingoscan-v1:" + serial).utf8))).lowercaseHex
        } else if let known = ledger.imported[id]?.sensorSerialHash {
            hash = known
        } else {
            return nil
        }
        let record = state.activation
        let updated = RecoveryPayload.utcString(record.updatedAt)
        let authenticated = record.state == .authenticated && secrets.kAuth != nil
        let serial = secrets.serial.flatMap { $0.utf8.count == 9 ? $0 : nil }
        let firmware = state.firmwareHex.utf8.count == 8 && Data(lowercaseHex: state.firmwareHex) != nil
            && state.firmwareHex == state.firmwareHex.lowercased() ? state.firmwareHex : nil
        let session = RecoveryPayload.Session(
            sessionID: id,
            sensorSerial: serial,
            sensorSerialHash: hash,
            productType: Int(state.productType),
            securityVersion: Int(state.securityVersion),
            firmwareHex: firmware,
            patchInfoHex: secrets.patchInfoRaw?.lowercaseHex,
            attemptID: record.attemptID,
            sequence: 1,
            updatedAtUTC: updated,
            activation: .init(
                state: record.state,
                attemptedAtUTC: nil,
                // En `prepared` aún no se ha usado: el Receiver ID va en `receiver_id`.
                receiverIDUsed: record.state == .prepared ? nil : receiverID,
                activationTimeEpochS: state.activationTimeEpochS,
                commandHex: nil,
                responseHex: secrets.activationResponse?.lowercaseHex,
                error: record.state == .failed ? record.failureReason : nil
            ),
            ble: .init(
                address: secrets.bleAddress,
                pinHex: secrets.pin?.lowercaseHex,
                peripheralUUIDLocal: state.peripheralUUID?.uuidString.lowercased()
            ),
            auth: .init(
                kAuthHex: secrets.kAuth?.lowercaseHex,
                kAuthCapturedAtUTC: authenticated ? updated : nil,
                lastSuccessfulHandshakeUTC: authenticated ? updated : nil,
                lastLifeCount: state.lastLifeCount
            ),
            sensorCertificateHex: nil
        )
        return (session, receiverID, state)
    }

    private func appIdentity(for state: PairingState, includeMaterial: Bool) async throws -> RecoveryPayload.AppIdentity {
        let identity = try? await credentials?.identity(for: state.family == .unknown ? .lingo : state.family)
        guard let identity else {
            if includeMaterial { throw RecoveryServiceError.identityUnavailable }
            return .init(label: state.identityLabel ?? "sin-identidad", productTypes: [state.productType],
                         securityVersions: [state.securityVersion], certificateSHA256: nil, patchSigningKeySHA256: nil)
        }
        let certificateHash = Data(SHA256.hash(data: identity.certificate.raw)).lowercaseHex
        let signingHash = identity.patchSigningPublicKey.map { Data(SHA256.hash(data: $0)).lowercaseHex }
        var material: RecoveryPayload.AppIdentity.Material?
        if includeMaterial {
            guard let signing = identity.patchSigningPublicKey else { throw RecoveryServiceError.identityUnavailable }
            material = .init(privateKeyHex: identity.privateKey.rawRepresentation.lowercaseHex,
                             certificateHex: identity.certificate.raw.lowercaseHex,
                             patchSigningPublicKeyHex: signing.lowercaseHex)
        }
        return .init(
            label: identity.label,
            productTypes: identity.productTypes ?? [state.productType],
            securityVersions: identity.securityVersions ?? [state.securityVersion],
            certificateSHA256: certificateHash,
            patchSigningKeySHA256: signingHash,
            includeMaterial: includeMaterial,
            material: material
        )
    }

    // MARK: - Estado para la UI

    func status() -> Status {
        Status(
            hasPassphrase: passphrase != nil,
            passphraseRemembered: passphraseRemembered,
            pendingSessionIDs: ledger.pendingSessionIDs,
            lastExport: ledger.lastExport,
            lastError: lastError,
            conflicts: ledger.conflicts,
            historical: ledger.historical,
            imported: ledger.imported.values.sorted { $0.importedAt > $1.importedAt },
            exportFolderName: folder.url.lastPathComponent,
            exportFolderKind: folder.kind
        )
    }

    func updates() -> AsyncStream<Status> {
        let (stream, continuation) = AsyncStream.makeStream(of: Status.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        observers[id] = continuation
        continuation.yield(status())
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    /// Sesión importada más reciente con lo que "Conectar sensor activo" puede mostrar (sin secretos completos).
    func latestImportedSession() async -> ImportedSessionDetail? {
        guard let record = ledger.imported.values.max(by: { $0.importedAt < $1.importedAt }),
              let state = try? await pairingStore.loadState(sessionID: record.sessionID),
              let secrets = try? await pairingStore.loadSecrets(sessionID: record.sessionID) else { return nil }
        return ImportedSessionDetail(
            sessionID: record.sessionID,
            state: state.activation.state,
            sequence: record.sequence,
            fromAppID: record.fromAppID,
            receiverIDMasked: secrets.receiverID.map(Self.maskedReceiverID),
            hasPIN: secrets.pin?.count == 4,
            hasKAuth: secrets.kAuth?.count == 16,
            paused: state.collectorPaused,
            openConflicts: ledger.conflicts.filter { $0.sessionID == record.sessionID }.count
        )
    }

    /// Receiver ID parcial: solo los 4 últimos dígitos decimales.
    static func maskedReceiverID(_ value: UInt32) -> String {
        let digits = String(value)
        return String(repeating: "•", count: max(0, digits.count - 4)) + digits.suffix(4)
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    private func publish() {
        let snapshot = status()
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    // MARK: - Persistencia auxiliar

    private func saveLedger() {
        do {
            try FileManager.default.createDirectory(at: ledgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try encoder.encode(ledger).write(to: ledgerURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            lastError = "registro de recuperación no guardado: \(type(of: error))"
        }
    }

    private func saveEvidence() {
        guard let evidenceItem else { return }
        do {
            try evidenceItem.save(JSONEncoder().encode(evidence))
        } catch {
            lastError = "evidencia de conflictos no guardada en el llavero: \(type(of: error))"
        }
    }

    private func log(_ level: EventLogLevel, _ message: LogMessage) async {
        try? await store?.logEvent(level, category: "recovery", message)
    }
}

// MARK: - Tipos

extension RecoveryService {
    enum RecoveryServiceError: Error, Equatable, CustomStringConvertible {
        case passphraseRequired
        case passphraseTooShort(minimum: Int)
        case nothingToExport
        case sessionIncomplete(String)
        case identityUnavailable
        case missingPatchInfo
        case incompleteForAstra
        case unreadableFile

        var description: String {
            switch self {
            case .passphraseRequired: String(localized: "recovery.error.passphrase", defaultValue: "Falta la frase de recuperación")
            case .passphraseTooShort(let n): String(localized: "recovery.error.short", defaultValue: "La frase debe tener al menos \(n) caracteres")
            case .nothingToExport: String(localized: "recovery.error.nothing", defaultValue: "No hay sesión que exportar")
            case .sessionIncomplete(let id): String(localized: "recovery.error.incomplete", defaultValue: "La sesión \(id) no tiene Receiver ID o serial")
            case .missingPatchInfo: "Faltan los datos originales del sensor. Esta sesión antigua no se puede exportar para Astra de forma segura."
            case .incompleteForAstra: "La sesión no contiene los datos completos y coherentes necesarios para Astra."
            case .identityUnavailable: String(localized: "recovery.error.identity", defaultValue: "No hay identidad de app con clave de firma")
            case .unreadableFile: String(localized: "recovery.error.unreadable", defaultValue: "No se pudo leer el archivo")
            }
        }
    }

    struct ExportedSession: Sendable, Equatable, Codable, Identifiable {
        let sessionID: String
        var id: String { sessionID }
        let sequence: Int
        let state: ActivationState
    }

    struct ExportRecord: Sendable, Equatable, Codable {
        let fileName: String
        let fileURL: URL
        let at: Date
        /// `prepared`, `response_saved`, `authenticated`, `manual` o `pendiente`.
        let trigger: String
        let sessions: [ExportedSession]
    }

    struct ImportRecord: Sendable, Equatable, Codable {
        let sessionID: String
        let archiveID: String
        let fromAppID: String
        let attemptID: String
        let state: ActivationState
        let sequence: Int
        let sensorSerialHash: String
        let importedAt: Date
    }

    struct ConflictSummary: Sendable, Equatable, Codable, Identifiable {
        let sessionID: String
        let attemptID: String
        let fields: [String]
        let localSequence: Int
        let remoteSequence: Int
        let remoteExporter: String
        let archiveID: String
        let at: Date
        var id: String { "\(sessionID)|\(archiveID)|\(remoteSequence)" }
    }

    struct HistoricalSummary: Sendable, Equatable, Codable, Identifiable {
        let sessionID: String
        let attemptID: String
        let sequence: Int
        let state: ActivationState
        let remoteExporter: String
        let archiveID: String
        let at: Date
        var id: String { "\(sessionID)|\(attemptID)|\(sequence)|\(archiveID)" }
    }

    /// Registro durable sin secretos (`recovery-ledger.json`).
    struct Ledger: Sendable, Equatable, Codable {
        var exportSequences: [String: Int] = [:]
        var activeExporters: [String: String] = [:]
        var pendingSessionIDs: [String] = []
        var lastExport: ExportRecord?
        var imported: [String: ImportRecord] = [:]
        var conflicts: [ConflictSummary] = []
        var historical: [HistoricalSummary] = []
        var aliases: [String: String] = [:]
    }

    /// Copias íntegras de conflictos e intentos históricos (con secretos): solo en el Keychain.
    struct Evidence: Sendable, Equatable, Codable {
        var conflicts: [RecoveryMergeConflict] = []
        var historical: [RecoveryMergeHistoricalAttempt] = []
    }

    struct ImportReport: Sendable, Equatable {
        let archiveID: String
        let exporter: String
        let decisions: [RecoveryMergeDecision]

        var changedSessions: [String] {
            decisions.compactMap {
                switch $0 {
                case .importedNew(let id), .replacedByRemote(let id, _, _): id
                default: nil
                }
            }
        }
        var conflictCount: Int { decisions.filter { if case .secretConflict = $0 { true } else { false } }.count }
        var historicalCount: Int { decisions.filter { if case .historicalAttempt = $0 { true } else { false } }.count }
    }

    /// Dónde se escribe el archivo de recuperación y por qué.
    struct ExportFolder: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            /// Carpeta elegida por Juampa (bookmark del archivo `.lingoscan`).
            case chosen
            /// Carpeta fija pasada al `init` (tests).
            case fixed
            /// Sin carpeta elegida: contenedor iCloud propio de la app.
            case appICloudContainer
            /// Sin carpeta ni iCloud: `Documents/` de la app.
            case documents
            /// Había carpeta elegida pero el bookmark ya no resuelve: se escribe en `Documents/` y la UI avisa.
            case unavailable
        }
        let url: URL
        let kind: Kind
    }

    struct Status: Sendable, Equatable {
        var hasPassphrase: Bool
        var passphraseRemembered: Bool
        var pendingSessionIDs: [String]
        var lastExport: ExportRecord?
        var lastError: String?
        var conflicts: [ConflictSummary]
        var historical: [HistoricalSummary]
        var imported: [ImportRecord]
        var exportFolderName: String
        var exportFolderKind: ExportFolder.Kind

        /// `true` salvo que se escriba en la carpeta elegida por Juampa (o la fija de los tests).
        var exportFolderIsFallback: Bool { exportFolderKind != .chosen && exportFolderKind != .fixed }

        static let empty = Status(hasPassphrase: false, passphraseRemembered: false, pendingSessionIDs: [], lastExport: nil,
                                  lastError: nil, conflicts: [], historical: [], imported: [], exportFolderName: "Documents",
                                  exportFolderKind: .documents)
    }

    struct ImportedSessionDetail: Sendable, Equatable {
        let sessionID: String
        let state: ActivationState
        let sequence: Int
        let fromAppID: String
        let receiverIDMasked: String?
        let hasPIN: Bool
        let hasKAuth: Bool
        let paused: Bool
        let openConflicts: Int

        /// Solo `response_saved` (handshake completo) y `authenticated` (kAuth/PIN, o completo) se conectan.
        var isConnectable: Bool { (state == .responseSaved || state == .authenticated) && hasPIN && openConflicts == 0 }
    }
}
