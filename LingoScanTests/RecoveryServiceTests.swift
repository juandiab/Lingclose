import CryptoKit
import Foundation
import LingoCore
import Testing
@testable import LingoScan

/// T-19 parte 2: `RecoveryService` + `LiveRecoveryExportHook` sobre el coordinador con dobles
/// (`InMemoryPairingStateStore` de T-08). PBKDF2 con 1 000 iteraciones para ir rápido.
@Suite(.serialized)
struct RecoveryServiceTests {
    static let passphrase = "frase de prueba sintética"

    static func tempDir(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "t19-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeService(pairing: any PairingStatePersisting, credentials: (any PairingCredentialsProviding)?,
                            store: SQLiteStore?, exportDir: URL) throws -> RecoveryService {
        RecoveryService(pairingStore: pairing, credentials: credentials, store: store, exportDirectory: exportDir,
                        stateDirectory: try tempDir("state"), evidenceItem: nil, iterations: 1_000)
    }

    /// Archivos exportados, descifrados y ordenados por `sequence` de su primera sesión.
    static func exported(_ dir: URL) throws -> [(name: String, data: Data, payload: RecoveryPayload)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
        return try names.map { name in
            let data = try Data(contentsOf: dir.appending(path: name))
            let plain = try RecoveryCrypto.open(try RecoveryEnvelope.decode(data), passphrase: passphrase)
            return (name, data, try RecoveryPayload.decode(plain))
        }.sorted { $0.payload.sessions[0].sequence < $1.payload.sessions[0].sequence }
    }

    /// Activa con el coordinador y devuelve harness, servicio, carpeta de exportación y sesión.
    static func pairedWithExports(passphraseFirst: Bool = true) async throws
        -> (CoordinatorHarness, RecoveryService, URL, String) {
        let hook = LiveRecoveryExportHook()
        let pairing = InMemoryPairingStateStore(recoveryHook: hook)
        let h = try await CoordinatorHarness(pairing: pairing)
        let dir = try tempDir("export")
        let service = try makeService(pairing: pairing, credentials: h.credentials, store: h.store, exportDir: dir)
        if passphraseFirst { try await service.setPassphrase(passphrase) }
        await hook.attach(service)
        let prepared = try await h.pairUntilSubscribed()
        return (h, service, dir, prepared.sessionID)
    }

    @Test func exportsAtTheThreeTransitionsWithSequence123() async throws {
        let (h, service, dir, sessionID) = try await Self.pairedWithExports()
        let files = try Self.exported(dir)
        #expect(files.count == 3)
        #expect(files.map { $0.payload.sessions[0].sequence } == [1, 2, 3])
        #expect(files.map { $0.payload.sessions[0].activation.state } == [.prepared, .responseSaved, .authenticated])
        for file in files {
            #expect(file.name.hasPrefix("LingoScan-lingoscan-"))
            #expect(file.name.hasSuffix(".lingoscan-recovery.json"))
            let p = file.payload
            #expect(p.sessions.count == 1 && p.sessions[0].sessionID == sessionID)
            #expect(p.receiverID == 0x1234_5678)
            #expect(p.appIdentity.label == "synthetic-lingo")
            #expect(p.appIdentity.includeMaterial == false && p.appIdentity.material == nil)
            #expect(p.appIdentity.certificateSHA256 == Data(SHA256.hash(data: h.credentials.appIdentity.certificate.raw)).lowercaseHex)
            #expect(p.appIdentity.patchSigningKeySHA256 != nil)
            #expect(p.sessions[0].attemptID == files[0].payload.sessions[0].attemptID, "mismo attempt_id")
        }
        let secrets = await h.pairing.loadSecrets(sessionID: sessionID)
        let last = files[2].payload.sessions[0]
        #expect(last.ble.pinHex == secrets.pin?.lowercaseHex)
        #expect(last.auth.kAuthHex == secrets.kAuth?.lowercaseHex)
        #expect(last.activation.responseHex == secrets.activationResponse?.lowercaseHex)
        #expect(files[0].payload.sessions[0].activation.receiverIDUsed == nil, "en prepared no se ha usado aún")
        #expect(files[0].payload.sessions[0].ble.pinHex == nil)
        #expect(await service.status().pendingSessionIDs.isEmpty)

        // Ningún log lleva PIN ni kAuth en claro.
        let logs = try await h.store.recentLogEvents(limit: 500).map(\.message)
        let pinHex = try #require(secrets.pin).lowercaseHex
        let kAuthHex = try #require(secrets.kAuth).lowercaseHex
        #expect(!logs.contains { $0.contains(pinHex) || $0.contains(kAuthHex) })
        #expect(logs.contains { $0.contains("recuperación exportada") })
    }

    @Test func reimportingCopy1AfterCopy3ChangesNothing() async throws {
        let (h, service, dir, sessionID) = try await Self.pairedWithExports()
        let files = try Self.exported(dir)
        let stateBefore = try #require(await h.pairing.loadState(sessionID: sessionID))
        let secretsBefore = await h.pairing.loadSecrets(sessionID: sessionID)
        let linkConnectsBefore = await h.link.connectCount

        let report = try await service.importData(files[0].data)
        #expect(report.decisions == [.keptLocal(sessionID: sessionID)])
        #expect(await h.pairing.loadState(sessionID: sessionID) == stateBefore)
        #expect(await h.pairing.loadSecrets(sessionID: sessionID) == secretsBefore)
        let status = await service.status()
        #expect(status.conflicts.isEmpty && status.historical.isEmpty && status.imported.isEmpty)
        #expect(await h.link.connectCount == linkConnectsBefore, "importar no toca BLE")
        #expect(try Self.exported(dir).count == 3, "importar no exporta")
    }

    @Test func withoutPassphraseExportsArePendingAndFlushedLater() async throws {
        let (_, service, dir, sessionID) = try await Self.pairedWithExports(passphraseFirst: false)
        #expect(try Self.exported(dir).isEmpty)
        #expect(await service.status().pendingSessionIDs == [sessionID])
        try await service.setPassphrase(Self.passphrase)
        let files = try Self.exported(dir)
        #expect(files.count == 1)
        #expect(files[0].payload.sessions[0].sequence == 1)
        #expect(files[0].payload.sessions[0].activation.state == .authenticated)
        #expect(await service.status().pendingSessionIDs.isEmpty)
        await #expect(throws: RecoveryService.RecoveryServiceError.self) { try await service.setPassphrase("corta") }
    }

    @Test func importIntoAnotherStoreMarksImportedPausedAndDetectsConflicts() async throws {
        let (h, _, dir, sessionID) = try await Self.pairedWithExports()
        let files = try Self.exported(dir)
        let original = await h.pairing.loadSecrets(sessionID: sessionID)

        // App destino: otro almacén, sin coordinador ni NFC/BLE.
        let target = InMemoryPairingStateStore(recoveryHook: LiveRecoveryExportHook())
        let targetDir = try Self.tempDir("target")
        let service = try Self.makeService(pairing: target, credentials: nil, store: nil, exportDir: targetDir)
        try await service.setPassphrase(Self.passphrase)

        let report = try await service.importData(files[2].data)
        #expect(report.decisions == [.importedNew(sessionID: sessionID)])
        let state = try #require(await target.loadState(sessionID: sessionID))
        #expect(state.activation.state == .authenticated)
        #expect(state.activation.attemptID == files[2].payload.sessions[0].attemptID)
        #expect(state.collectorPaused, "importar no conecta")
        #expect(!state.profile(serial: "").isFresh, "un sensor importado nunca parece sin activar")
        let imported = await target.loadSecrets(sessionID: sessionID)
        #expect(imported == original)

        let detail = try #require(await service.latestImportedSession())
        #expect(detail.isConnectable && detail.hasKAuth && detail.paused)
        #expect(detail.receiverIDMasked == "•••••9896", "0x12345678 = 305419896: solo los 4 últimos dígitos")

        // Una copia anterior no retrocede.
        #expect(try await service.importData(files[0].data).decisions == [.keptLocal(sessionID: sessionID)])
        #expect(await target.loadState(sessionID: sessionID)?.activation.state == .authenticated)

        // Secreto contradictorio con sequence mayor: conflicto, local intacta, no conectable.
        var forged = files[2].payload
        forged.sessions[0].sequence = 7
        forged.sessions[0].ble.pinHex = "ffffffff"
        let envelope = try RecoveryCrypto.seal(
            plaintext: try forged.encoded(), passphrase: Self.passphrase, archiveID: UUID().uuidString.lowercased(),
            createdAtUTC: forged.exportedAtUTC, producer: .init(appID: "com.otalvaro.lingoscan.astra", producerTag: "astra", appVersion: "t"),
            iterations: 1_000
        )
        let conflictReport = try await service.importData(try envelope.encoded())
        #expect(conflictReport.decisions == [.secretConflict(sessionID: sessionID, fields: ["ble.pin_hex"])])
        #expect(await target.loadSecrets(sessionID: sessionID) == original)
        #expect(await service.status().conflicts.count == 1)
        #expect(try await service.latestImportedSession()?.isConnectable == false)
        // Idempotente: la misma copia conflictiva no se duplica.
        _ = try await service.importData(try envelope.encoded())
        #expect(await service.status().conflicts.count == 1)

        // Frase incorrecta: se rechaza sin distinguir la causa.
        try await service.setPassphrase("otra frase distinta larga")
        await #expect(throws: RecoveryCryptoError.authenticationFailed) { try await service.importData(files[2].data) }
    }
}
