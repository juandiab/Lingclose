import CryptoKit
import Foundation
import Testing
@testable import LingoCore

/// Ida y vuelta exportar → importar, protocolo de escritura (§3.1), formato del CSV y retención (§3.3).
@Suite("Archive · exportar e importar")
struct ArchiveRoundTripTests {
    static let appID = "com.otalvaro.lingoscan"
    static let t0 = TestSupport.activationEpoch

    /// Base con una sesión real de 120 min, con tombstone, exclusiones, eventos con linaje, ledger y un conflicto.
    static func populate(_ store: SQLiteStore, session: SensorSessionRecord = TestSupport.session()) async throws -> SensorSessionRecord {
        try await store.upsertSession(session)
        var readings: [GlucoseReading] = []
        for lc in 1...120 {
            let q = lc <= 3
            let origin: ReadingOrigin = lc % 10 == 0 ? .backfillHistory : .live
            let raw = RawReading(
                capped: q ? nil : 90 + lc % 40, uncapped: q ? nil : 92 + lc % 40, historicLifeCount: max(lc - 18, 0), rateCenti: q ? nil : 5,
                trend: 3, actionable: false, temperatureCenti: 3200, rangeBits: 0, qualityFlag: q, channel: 1,
                reservedHex: "00112233445566778899aabbccddeeff")
            readings.append(TestSupport.reading(session, lc: lc, raw: raw, origin: origin))
        }
        readings.append(TestSupport.reading(session, lc: 130, raw: TestSupport.raw(uncapped: 520, capped: 510), origin: .live))  // fuera de rango
        try await store.insertReadings(readings)
        try await store.deleteReading(recordID: RecordID.make(sessionID: session.sessionID, lifeCount: 77))

        let id = TestSupport.newID, at = UTCInstant(epochSeconds: t0 + 3_600)
        let mealID = id(), e1 = id(), e2 = id()
        let meal1 = DiaryEvent(eventID: mealID, kind: .meal, at: at, tz: TestSupport.tz, carbsG: 45, text: "Arroz", createdAt: at, updatedAt: at,
                               editID: e1, editedByAppID: appID, synthetic: false)
        try await store.upsertEvent(meal1)
        let meal2 = DiaryEvent(eventID: mealID, kind: .meal, at: at, tz: TestSupport.tz, carbsG: 60, text: "Arroz con pollo", createdAt: at, updatedAt: at.adding(seconds: 60),
                               revision: 2, editID: e2, parentEditID: e1, editedByAppID: appID, synthetic: false)
        try await store.upsertEvent(meal2)
        let noteID = id(), n1 = id(), n2 = id()
        try await store.upsertEvent(DiaryEvent(eventID: noteID, kind: .note, at: at, tz: TestSupport.tz, text: "x", createdAt: at, updatedAt: at, editID: n1, editedByAppID: appID, synthetic: false))
        try await store.upsertEvent(DiaryEvent(eventID: noteID, kind: .note, at: at, tz: TestSupport.tz, createdAt: at, updatedAt: at.adding(seconds: 5), revision: 2,
                                               editID: n2, parentEditID: n1, editedByAppID: appID, deleted: true, synthetic: false))
        for lc in 60...64 {
            let rid = RecordID.make(sessionID: session.sessionID, lifeCount: lc)
            if lc == 62 {
                try await store.appendLedger(HealthLedgerEntry(attemptID: id(), subjectID: rid, subjectKind: .glucose, writerAppID: appID, syncIdentifier: rid, syncVersion: 1, exportedAt: UTCInstant(epochSeconds: t0 + 4_000), result: .failed))
            }
            try await store.appendLedger(HealthLedgerEntry(attemptID: id(), subjectID: rid, subjectKind: .glucose, writerAppID: appID, syncIdentifier: rid, syncVersion: 1, exportedAt: UTCInstant(epochSeconds: t0 + 4_000 + Int64(lc)), result: .written))
        }
        try await store.appendLedger(HealthLedgerEntry(attemptID: id(), subjectID: mealID, subjectKind: .carbs, writerAppID: appID, syncIdentifier: mealID, syncVersion: 2, exportedAt: UTCInstant(epochSeconds: t0 + 4_100), result: .written))
        let r90 = try #require(try await store.reading(recordID: RecordID.make(sessionID: session.sessionID, lifeCount: 90)))
        try await store.appendConflict(ConflictRecord(at: UTCInstant(epochSeconds: t0 + 5_000), kind: .reading, id: r90.recordID, resolution: .keptLocal,
                                                      local: try JSONValue.encoding(r90), remote: try JSONValue.encoding(r90), remoteArchiveID: id()))
        return session
    }

    static func exporter(_ store: SQLiteStore, path: String, interruption: LingoScanArchiveWriter.Interruption? = nil,
                         health: ArchiveHealthState = .lingoScanActive) -> ArchiveExporter {
        ArchiveExporter(store: store, databasePath: path, writer: LingoScanArchiveWriter(producer: ArchiveTestSupport.producer, interruption: interruption),
                        health: { health }, now: ArchiveTestSupport.fixedNow)
    }

    @Test("el paquete exportado sigue el protocolo, el nombre y el contenido del contrato y se registra")
    func exportsContractPackage() async throws {
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path, now: ArchiveTestSupport.fixedNow)
        let session = try await Self.populate(store)
        let dest = try ArchiveTestSupport.temporaryDirectory("destino")
        let result = try await Self.exporter(store, path: path).export(to: dest)

        #expect(result.verified, "\(result.verificationFailure ?? "")")
        #expect(result.url.lastPathComponent == "LingoScan-lingoscan-\(ArchivePackageName(producerTag: "lingoscan", createdAt: result.manifest.createdAt, archiveID: result.archiveID).timestamp)-\(result.archiveID.prefix(8)).lingoscan")
        #expect(ArchivePackageName(parsing: result.url.lastPathComponent) != nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: dest.path)
        #expect(names == [result.url.lastPathComponent], "no debe quedar ninguna carpeta .partial")
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: result.url.path))
        #expect(files == ["manifest.json", "sessions.json", "readings.ndjson", "events.ndjson", "health_export_ledger.ndjson", "conflicts.ndjson", "readings.csv", "README.md"])

        let m = result.manifest
        #expect(m.contractVersion == "1.0.0-draft.4" && m.schemaVersion == 1)
        #expect(m.producer.producerTag == "lingoscan" && m.producer.appID == "com.otalvaro.lingoscan")
        #expect(m.snapshot.complete && m.snapshot.kind == .full && m.snapshot.from == nil)
        #expect(!m.synthetic)
        #expect(m.policy.eligibilityPolicyID == "lingoscan-v1")
        #expect(m.counts == .init(sessions: 1, readings: 121, events: 2, ledgerEntries: 7, conflicts: 1))
        #expect(m.health.writerAppID == appIDConstant && m.health.handoverAt == nil)
        // Elegibles: lc 60...120 salvo el tombstone 77 (60); 5 escritas (60...64) → 55 pendientes; la comida ya está escrita.
        #expect(m.health.pendingSubjects == 55)
        _ = session
        #expect(m.health.lastConfirmedMeasuredAt == UTCInstant(epochSeconds: Self.t0 + 60 * 64))

        // Cada archivo listado coincide con su SHA-256 calculado aparte.
        for entry in m.files {
            let data = try Data(contentsOf: result.url.appending(path: entry.name))
            #expect(data.count == entry.bytes)
            #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == entry.sha256)
        }
        // El manifest se registra con su hash y la ruta; nada más.
        #expect(try await store.isArchiveKnown(result.archiveID))
        // Contenido fijo.
        let readme = try String(contentsOf: result.url.appending(path: "README.md"), encoding: .utf8)
        #expect(readme == LingoScanArchiveWriter.readmeText)
    }

    private var appIDConstant: String { Self.appID }

    @Test("readings.csv: cabecera exacta de §5.6, una fila por lectura y comillas solo cuando hacen falta")
    func csvHeaderAndRows() async throws {
        #expect(CSVWriter.header == "record_id,session_id,life_count,measured_at_utc,measured_at_local,tz,origin,value_mgdl,eligible,exclusion_reason,trend,rate_centi,quality_flag")
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path, now: ArchiveTestSupport.fixedNow)
        let session = try await Self.populate(store)
        let result = try await Self.exporter(store, path: path).export(to: try ArchiveTestSupport.temporaryDirectory())
        let text = try String(contentsOf: result.url.appending(path: "readings.csv"), encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first.map(String.init) == CSVWriter.header)
        #expect(lines.count == 121 + 2)  // cabecera + 121 + línea vacía final
        #expect(lines.last == "")
        // lc 1: con bit 15, sin valor, hora local de Bogotá (UTC-5).
        let row1 = try #require(lines.first { $0.hasPrefix("\(session.sessionID):glucose:1,") })
        let fields = row1.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(fields.count == 13)
        #expect(fields[3] == UTCInstant(epochSeconds: Self.t0 + 60).rfc3339)
        #expect(fields[4] == "2026-10-27T07:01:00-05:00")
        #expect(fields[5] == "America/Bogota" && fields[6] == "live" && fields[7] == "" && fields[8] == "false")
        #expect(fields[9] == "quality_flag" && fields[12] == "true")
        #expect(CSVWriter.escape("a,b") == "\"a,b\"" && CSVWriter.escape("plain") == "plain" && CSVWriter.escape("q\"q") == "\"q\"\"q\"")
    }

    @Test("ida y vuelta: base vacía → mismos record_id, raw, elegibilidad, eventos, ledger y conflictos")
    func roundTrip() async throws {
        let pathA = try TestSupport.temporaryDatabasePath("a")
        let storeA = try SQLiteStore(path: pathA, now: ArchiveTestSupport.fixedNow)
        _ = try await Self.populate(storeA)
        let result = try await Self.exporter(storeA, path: pathA).export(to: try ArchiveTestSupport.temporaryDirectory())

        let pathB = try TestSupport.temporaryDatabasePath("b")
        let storeB = try SQLiteStore(path: pathB, now: ArchiveTestSupport.fixedNow)
        let summary = try ArchiveImporter(databasePath: pathB, now: ArchiveTestSupport.fixedNow).importPackage(at: result.url)
        #expect(summary.readings.new == 121 && summary.readings.conflicted == 0 && summary.rejected == 0)
        #expect(summary.sessions.new == 1 && summary.events.new == 2 && summary.ledger.new == 7)

        let a = try ArchiveSnapshotReader(databasePath: pathA).snapshot()
        let b = try ArchiveSnapshotReader(databasePath: pathB).snapshot()
        #expect(a.sessions.count == b.sessions.count)
        func stripImported(_ r: GlucoseReading) -> GlucoseReading { var r = r; r.importedFrom = nil; return r }
        #expect(a.readings.map(stripImported) == b.readings.map(stripImported))
        #expect(b.readings.allSatisfy { $0.importedFrom?.archiveID == result.archiveID })
        #expect(a.readings.map(\.recordID) == b.readings.map(\.recordID))
        #expect(a.readings.map(\.raw) == b.readings.map(\.raw))
        #expect(a.readings.map(\.eligibility) == b.readings.map(\.eligibility))
        func stripEvent(_ e: ArchiveEvent) -> ArchiveEvent { var e = e; e.event.importedFrom = nil; return e }
        #expect(a.events.sorted { $0.event.eventID < $1.event.eventID }.map(stripEvent) == b.events.sorted { $0.event.eventID < $1.event.eventID }.map(stripEvent))
        #expect(a.ledger.sorted { $0.attemptID < $1.attemptID } == b.ledger.sorted { $0.attemptID < $1.attemptID })
        // Sesión: mismos campos salvo la procedencia.
        var sa = a.sessions[0]; sa.importedFrom = nil
        var sb = b.sessions[0]; sb.importedFrom = nil
        #expect(sa == sb)
        // El estado derivado de Health y los pendientes son los mismos.
        #expect(ArchiveHealthDerivation.pendingSubjects(readings: a.readings, events: a.events.map(\.event), ledger: a.ledger).map(\.subjectID)
                == ArchiveHealthDerivation.pendingSubjects(readings: b.readings, events: b.events.map(\.event), ledger: b.ledger).map(\.subjectID))
        // Los conflictos del paquete son evidencia: no se importan.
        #expect(b.conflicts.isEmpty)

        // Reexportar desde B: los mismos sujetos, con la procedencia (`imported_from`) como única diferencia.
        let again = try await Self.exporter(storeB, path: pathB).export(to: try ArchiveTestSupport.temporaryDirectory())
        #expect(again.verified)
        #expect(again.manifest.counts == .init(sessions: 1, readings: 121, events: 2, ledgerEntries: 7, conflicts: 0))
        #expect(again.manifest.health.pendingSubjects == result.manifest.health.pendingSubjects)
    }

    @Test("exportar los ancestros: edit_ancestors completo y sin inventar ninguno")
    func exportsEditAncestors() async throws {
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path, now: ArchiveTestSupport.fixedNow)
        _ = try await Self.populate(store)
        let snapshot = try ArchiveSnapshotReader(databasePath: path).snapshot()
        let edited = try #require(snapshot.events.first { $0.event.kind == .meal })
        #expect(edited.ancestors?.count == 1)
        #expect(edited.ancestors?.first?.editID == edited.event.parentEditID)
        // Un evento importado sin eslabón intermedio no se exporta con una cadena inventada.
        let orphan = DiaryEvent(eventID: TestSupport.newID(), kind: .note, at: UTCInstant(epochSeconds: Self.t0), tz: TestSupport.tz, createdAt: UTCInstant(epochSeconds: Self.t0), updatedAt: UTCInstant(epochSeconds: Self.t0),
                                revision: 3, editID: TestSupport.newID(), parentEditID: TestSupport.newID(), editedByAppID: "com.otalvaro.lingoscan.astra", synthetic: false)
        try await store.upsertEvent(orphan)
        let after = try ArchiveSnapshotReader(databasePath: path).snapshot()
        #expect(after.events.first { $0.event.eventID == orphan.eventID }?.ancestors == nil)
        let json = try LingoScanArchiveWriter.eventJSON(try #require(after.events.first { $0.event.eventID == orphan.eventID }))
        #expect(json.value(at: "edit_ancestors") == .null)
    }

    // MARK: Corte durante la exportación

    @Test("un corte simulado en cada paso deja solo la carpeta .partial y no registra nada", arguments: [
        ArchiveExportStep.partialCreated, .dataFilesWritten, .manifestWritten,
    ])
    func interruptedExportLeavesOnlyPartial(step: ArchiveExportStep) async throws {
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path, now: ArchiveTestSupport.fixedNow)
        _ = try await Self.populate(store)
        let dest = try ArchiveTestSupport.temporaryDirectory("destino")
        let exporter = Self.exporter(store, path: path, interruption: { s in if s == step { throw ArchiveSimulatedInterruption(step: s) } })
        do {
            _ = try await exporter.export(to: dest)
            Issue.record("la exportación debió cortarse")
        } catch let e as ArchiveSimulatedInterruption {
            #expect(e.step == step)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: dest.path)
        #expect(names.count == 1 && names[0].hasSuffix(".lingoscan.partial"), "\(names)")
        // Sin renombrar no es un paquete: el lector lo ignora y la base no lo registra.
        do { _ = try LingoScanArchiveReader().readManifest(at: dest.appending(path: names[0])); Issue.record("debió ser partial") } catch let e as ArchiveValidationError { #expect(e == .partialPackage) }
        let archiveID8 = String(names[0].dropLast(".lingoscan.partial".count).suffix(8))
        #expect(archiveID8.count == 8)
        let rows = try await store.recentLogEvents()  // sin tocar el registro de eventos
        _ = rows
        #expect(try ArchiveImporter(databasePath: path).importAll(in: dest).isEmpty)
        // La siguiente exportación borra la parcial propia y deja un paquete íntegro.
        let ok = try await Self.exporter(store, path: path).export(to: dest)
        #expect(ok.removedPartials == names)
        #expect(ok.verified)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dest.path) == [ok.url.lastPathComponent])
        #expect(try await store.isArchiveKnown(ok.archiveID))
    }

    @Test("un corte no registra el paquete: archives sigue vacío")
    func interruptedExportIsNotRegistered() async throws {
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path, now: ArchiveTestSupport.fixedNow)
        _ = try await Self.populate(store)
        let dest = try ArchiveTestSupport.temporaryDirectory()
        let exporter = Self.exporter(store, path: path, interruption: { s in if s == .manifestWritten { throw ArchiveSimulatedInterruption(step: s) } })
        _ = try? await exporter.export(to: dest)
        let db = try ArchiveDatabase(path: path)
        #expect(try db.connection.queryFirst("SELECT COUNT(*) FROM archives") { $0.int(0) } == 0)
        #expect(try db.connection.queryFirst("SELECT COUNT(*) FROM imported_archives") { $0.int(0) } == 0)
    }

    @Test("las .partial de otro productor no se tocan")
    func foreignPartialsAreKept() throws {
        let dir = try ArchiveTestSupport.temporaryDirectory()
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appending(path: "LingoScan-astra-20261027T160500Z-ffffffff.lingoscan.partial"), withIntermediateDirectories: false)
        try fm.createDirectory(at: dir.appending(path: "LingoScan-lingoscan-20261027T160500Z-eeeeeeee.lingoscan.partial"), withIntermediateDirectories: false)
        let removed = try LingoScanArchiveWriter.removeAbandonedPartials(in: dir, producerTag: "lingoscan")
        #expect(removed == ["LingoScan-lingoscan-20261027T160500Z-eeeeeeee.lingoscan.partial"])
        #expect(try fm.contentsOfDirectory(atPath: dir.path) == ["LingoScan-astra-20261027T160500Z-ffffffff.lingoscan.partial"])
    }

    // MARK: Manifest sintético y health

    @Test("manifest.synthetic solo es true si todo lo exportado es sintético")
    func manifestSyntheticFlag() async throws {
        let session = TestSupport.session(synthetic: true)
        let r = TestSupport.reading(session, lc: 100, raw: TestSupport.raw(uncapped: 110, capped: 108), origin: .live)
        let writer = LingoScanArchiveWriter(producer: ArchiveTestSupport.producer)
        let dest = try ArchiveTestSupport.temporaryDirectory()
        let syn = try writer.write(ArchiveContent(sessions: [session], readings: [r]), createdAt: UTCInstant(epochSeconds: TestSupport.activationEpoch + 9_000), into: dest)
        #expect(syn.manifest.synthetic)
        _ = try LingoScanArchiveReader().read(at: syn.url)
        var real = TestSupport.session(); real.revision = 1
        let mixed = try writer.write(ArchiveContent(sessions: [session, real], readings: [r]), createdAt: UTCInstant(epochSeconds: TestSupport.activationEpoch + 9_001), into: dest)
        #expect(!mixed.manifest.synthetic)
        #expect(try writer.write(ArchiveContent(), createdAt: UTCInstant(epochSeconds: TestSupport.activationEpoch + 9_002), into: dest).manifest.synthetic == false)
    }

    @Test("handover_at_utc y writer_app_id viajan en manifest.health")
    func healthBlockCarriesHandover() async throws {
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path, now: ArchiveTestSupport.fixedNow)
        _ = try await Self.populate(store)
        let handover = UTCInstant(epochSeconds: Self.t0 + 7_200)
        let result = try await Self.exporter(store, path: path, health: ArchiveHealthState(writerAppID: Self.appID, handoverAt: handover))
            .export(to: try ArchiveTestSupport.temporaryDirectory())
        #expect(result.manifest.health.handoverAt == handover)
        let read = try LingoScanArchiveReader().read(at: result.url)
        #expect(read.manifest.health.handoverAt == handover)
        let summary = try ArchiveImporter(databasePath: try TestSupport.temporaryDatabasePath(), now: ArchiveTestSupport.fixedNow).importPackage(at: result.url)
        #expect(summary.handoverAt == handover)
    }

    // MARK: Retención

    @Test("retención: 7 últimos y el más reciente de cada mes; nunca paquetes de otro productor ni .partial")
    func retention() {
        func name(_ tag: String, _ ts: String, _ id: String) -> String { "LingoScan-\(tag)-\(ts)-\(id).lingoscan" }
        // 10 paquetes propios, uno por día, en octubre, y uno por mes anterior.
        var names: [String] = (1...10).map { name("lingoscan", String(format: "202610%02dT120000Z", $0), String(format: "%08x", $0)) }
        names += [name("lingoscan", "20260915T120000Z", "00000a01"), name("lingoscan", "20260920T120000Z", "00000a02"), name("lingoscan", "20260820T120000Z", "00000b01")]
        names += [name("astra", "20250101T000000Z", "99999999"), "LingoScan-lingoscan-20261011T120000Z-0000000f.lingoscan.partial", "notas.txt"]
        let doomed = ArchiveRetention.foldersToDelete(among: names, producerTag: "lingoscan")
        // Octubre: se conservan los 7 más recientes (4...10) y se borran 1, 2, 3 (el más reciente del mes ya está entre los 7).
        // Septiembre: se conserva solo el más reciente (0920); agosto: el único (0820).
        #expect(doomed.sorted() == [name("lingoscan", "20261001T120000Z", "00000001"), name("lingoscan", "20261002T120000Z", "00000002"),
                                    name("lingoscan", "20261003T120000Z", "00000003"), name("lingoscan", "20260915T120000Z", "00000a01")].sorted())
        #expect(!doomed.contains { $0.contains("astra") || $0.hasSuffix(".partial") })
    }

    @Test("la exportación aplica la retención sobre la carpeta destino")
    func exportAppliesRetention() async throws {
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path, now: ArchiveTestSupport.fixedNow)
        _ = try await Self.populate(store)
        let dest = try ArchiveTestSupport.temporaryDirectory()
        let fm = FileManager.default
        for day in 1...9 {  // 9 paquetes viejos ficticios del mismo mes anterior
            try fm.createDirectory(at: dest.appending(path: String(format: "LingoScan-lingoscan-202609%02dT120000Z-%08x.lingoscan", day, day)), withIntermediateDirectories: false)
        }
        try fm.createDirectory(at: dest.appending(path: "LingoScan-astra-20250101T000000Z-99999999.lingoscan"), withIntermediateDirectories: false)
        let result = try await Self.exporter(store, path: path).export(to: dest)
        // Se conservan los 7 más recientes (el nuevo + 6 de septiembre); el más reciente de cada mes ya está entre ellos.
        #expect(result.removedByRetention.count == 3)
        let left = try fm.contentsOfDirectory(atPath: dest.path)
        #expect(left.contains(result.url.lastPathComponent))
        #expect(left.contains("LingoScan-astra-20250101T000000Z-99999999.lingoscan"))
        #expect(left.filter { $0.contains("-lingoscan-") }.count == 7)
    }

    @Test("estado de iCloud por paquete (§3.2)")
    func uploadStates() {
        typealias S = ArchiveUploadState
        #expect(S.from(isUbiquitous: false, isUploaded: nil, isUploading: nil, errorDescription: nil) == .unknown)
        #expect(S.from(isUbiquitous: true, isUploaded: false, isUploading: true, errorDescription: nil) == .icloudUploading)
        #expect(S.from(isUbiquitous: true, isUploaded: true, isUploading: false, errorDescription: nil) == .icloudUploaded)
        #expect(S.from(isUbiquitous: true, isUploaded: false, isUploading: false, errorDescription: nil) == .localWritten)
        #expect(S.from(isUbiquitous: true, isUploaded: false, isUploading: false, errorDescription: "sin cuota") == .icloudError("sin cuota"))
        #expect(S.from(isUbiquitous: true, isUploaded: nil, isUploading: nil, errorDescription: nil) == .unknown)
        #expect(S.aggregate([.icloudUploaded, .icloudUploaded]) == .icloudUploaded)
        #expect(S.aggregate([.icloudUploaded, .icloudUploading]) == .icloudUploading)
        #expect(S.aggregate([.icloudUploaded, .localWritten]) == .localWritten)
        #expect(S.aggregate([.icloudUploaded, .icloudError("x"), .icloudUploading]) == .icloudError("x"))
        #expect(S.aggregate([]) == .unknown)
        #expect(!S.localWritten.isBackedUp && S.icloudUploaded.isBackedUp)
        #expect(S.icloudError("x").code == "icloud_error")
    }

    /// Con `LINGOSCAN_EXPORT_DIR` definida, deja paquetes exportados (propio, reexportado tras importar y del ejemplo
    /// importado) para pasarles `tools/verify_archive.py` desde fuera.
    @Test("paquetes para el verificador externo", .enabled(if: ProcessInfo.processInfo.environment["LINGOSCAN_EXPORT_DIR"] != nil))
    func exportForExternalVerifier() async throws {
        let out = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["LINGOSCAN_EXPORT_DIR"]), isDirectory: true)
        let pathA = try TestSupport.temporaryDatabasePath("a")
        let storeA = try SQLiteStore(path: pathA, now: ArchiveTestSupport.fixedNow)
        _ = try await Self.populate(storeA)
        let own = try await Self.exporter(storeA, path: pathA).export(to: out.appending(path: "propio", directoryHint: .isDirectory))
        let pathB = try TestSupport.temporaryDatabasePath("b")
        let storeB = try SQLiteStore(path: pathB, now: ArchiveTestSupport.fixedNow)
        _ = try ArchiveImporter(databasePath: pathB, now: ArchiveTestSupport.fixedNow).importPackage(at: own.url)
        _ = try ArchiveImporter(databasePath: pathB, now: ArchiveTestSupport.fixedNow)
            .importPackage(at: ArchiveTestSupport.examplesURL.appending(path: "LingoScan-lingoscan-20261027T150405Z-3fa85f64.lingoscan", directoryHint: .isDirectory))
        _ = try await Self.exporter(storeB, path: pathB).export(to: out.appending(path: "reexportado", directoryHint: .isDirectory))
    }
}
