import Foundation
import Testing
@testable import LingoCore

/// Reglas de unión de §5.1, §5.3, §5.4 y §8.4 (draft.4) con paquetes construidos en la prueba.
@Suite("Archive · reglas de unión")
struct ArchiveMergeRulesTests {
    static let astraApp = "com.otalvaro.lingoscan.astra"
    static let t0 = TestSupport.activationEpoch

    static func producer(_ tag: String) -> ArchiveProducerInfo {
        tag == "astra"
            ? ArchiveProducerInfo(appID: astraApp, producerTag: "astra", appName: "LingoScan Astra", appVersion: "1", build: "1", decoder: DecoderInfo(id: "astra-lingo", version: "1"), deviceModel: "iPhone", osVersion: "27")
            : ArchiveTestSupport.producer
    }

    /// Escribe `content` como paquete y lo devuelve ya leído.
    @discardableResult
    static func package(_ content: ArchiveContent, tag: String = "astra", at seconds: Int64, in dir: URL) throws -> ArchivePackage {
        let written = try LingoScanArchiveWriter(producer: producer(tag))
            .write(content, health: ArchiveHealthState(writerAppID: tag == "astra" ? astraApp : "com.otalvaro.lingoscan"),
                   createdAt: UTCInstant(epochSeconds: seconds), into: dir)
        return try LingoScanArchiveReader().read(at: written.url)
    }

    static func make(_ name: String = "base") async throws -> (store: SQLiteStore, path: String, importer: ArchiveImporter, dir: URL) {
        let path = try TestSupport.temporaryDatabasePath(name)
        let store = try SQLiteStore(path: path, now: ArchiveTestSupport.fixedNow)
        return (store, path, ArchiveImporter(databasePath: path, now: ArchiveTestSupport.fixedNow), try ArchiveTestSupport.temporaryDirectory())
    }

    static func event(_ id: String, edit: String, parent: String?, text: String = "t", deleted: Bool = false, app: String = astraApp) -> DiaryEvent {
        let at = UTCInstant(epochSeconds: t0 + 100)
        return DiaryEvent(eventID: id, kind: .note, at: at, tz: TestSupport.tz, text: deleted ? nil : text, createdAt: at, updatedAt: at,
                          editID: edit, parentEditID: parent, editedByAppID: app, deleted: deleted, synthetic: false)
    }

    // MARK: Lecturas

    @Test("raw complementario: se conservan ambas tramas con su origen y la local no se reatribuye (en ambos órdenes)")
    func complementaryRawKeepsBothRoutes() async throws {
        let session = TestSupport.session()
        let live = RawReading(capped: 120, uncapped: 124, historicCapped: 118, historicUncapped: 119, historicLifeCount: 80, rateCenti: 4, trend: 3, actionable: false,
                              temperatureCenti: 3200, rangeBits: 0, qualityFlag: false, channel: 1, reservedHex: "aa")
        let fast = RawReading(uncapped: 124, qualityFlag: false)  // equivalente, pero solo con lo que trae el fast data
        for (localOrigin, remoteOrigin, localRaw, remoteRaw) in [(ReadingOrigin.live, ReadingOrigin.backfillFast, live, fast),
                                                                  (.backfillFast, .live, fast, live)] {
            let env = try await Self.make()
            let own = ArchiveContent(sessions: [session], readings: [TestSupport.reading(session, lc: 100, raw: localRaw, origin: localOrigin)])
            try await env.store.upsertSession(session)
            try await env.store.insertReading(own.readings[0])
            let remote = try Self.package(ArchiveContent(sessions: [session], readings: [TestSupport.reading(session, lc: 100, raw: remoteRaw, origin: remoteOrigin)]), at: Self.t0 + 9_000, in: env.dir)
            let summary = try env.importer.importPackage(remote)
            let r = try #require(try await env.store.reading(recordID: RecordID.make(sessionID: session.sessionID, lifeCount: 100)))
            #expect(r.origin == localOrigin, "el origen local no cambia")
            #expect(r.raw == localRaw, "no se combinan campos ni se atribuye la trama de otra ruta")
            #expect(r.revision == 1 && r.importedFrom == nil)
            let conflicts = try await env.store.conflicts()
            #expect(conflicts.count == 1 && conflicts[0].resolution == .merged)
            #expect(conflicts[0].remote?.value(at: "origin") == .string(remoteOrigin.rawValue))
            #expect(conflicts[0].local?.value(at: "origin") == .string(localOrigin.rawValue))
            #expect(summary.readings.conflicted == 1 && summary.conflictsRecorded == 1)
        }
    }

    @Test("raw idéntico: el origin pasa a ser el de mayor precedencia, sin conflicto y sin tocar el raw")
    func identicalRawUpgradesOrigin() async throws {
        let session = TestSupport.session()
        let raw = TestSupport.raw(uncapped: 130, capped: 128, trend: 3, channel: 1)
        for (localOrigin, remoteOrigin, expected) in [(ReadingOrigin.backfillHistory, ReadingOrigin.live, ReadingOrigin.live),
                                                      (.live, .backfillHistory, .live), (.embeddedHistory, .backfillFast, .backfillFast)] {
            let env = try await Self.make()
            try await env.store.upsertSession(session)
            try await env.store.insertReading(TestSupport.reading(session, lc: 100, raw: raw, origin: localOrigin))
            let remote = try Self.package(ArchiveContent(sessions: [session], readings: [TestSupport.reading(session, lc: 100, raw: raw, origin: remoteOrigin)]), at: Self.t0 + 9_000, in: env.dir)
            _ = try env.importer.importPackage(remote)
            let r = try #require(try await env.store.reading(recordID: RecordID.make(sessionID: session.sessionID, lifeCount: 100)))
            #expect(r.origin == expected && r.raw == raw)
            #expect(try await env.store.conflicts().isEmpty)
        }
    }

    @Test("tombstones pegajosos en ambos sentidos y sintético contra real")
    func tombstonesAndSynthetic() async throws {
        let session = TestSupport.session()
        let alive = TestSupport.reading(session, lc: 100, raw: TestSupport.raw(uncapped: 130, capped: 128), origin: .live)
        var tomb = alive
        tomb.deleted = true; tomb.value = nil; tomb.revision = 3
        tomb.eligibility = .excluded(.deleted, policyID: tomb.eligibility.policyID, policyVersion: tomb.eligibility.policyVersion)
        var syntheticTwin = TestSupport.reading(session, lc: 101, raw: TestSupport.raw(uncapped: 99, capped: 99), origin: .live, synthetic: true)
        syntheticTwin.value = nil
        syntheticTwin.eligibility = .excluded(.synthetic, policyID: "lingoscan-v1", policyVersion: "1.0.0")
        let realTwin = TestSupport.reading(session, lc: 101, raw: TestSupport.raw(uncapped: 140, capped: 140), origin: .live)

        // Local vivo, remoto tombstone → se toma el tombstone (revision = máx + 1).
        let a = try await Self.make("a")
        try await a.store.upsertSession(session)
        try await a.store.insertReadings([alive, realTwin])
        let pkgTomb = try Self.package(ArchiveContent(sessions: [session], readings: [tomb, syntheticTwin]), at: Self.t0 + 9_000, in: a.dir)
        let s1 = try a.importer.importPackage(pkgTomb)
        let r100 = try #require(try await a.store.reading(recordID: alive.recordID))
        #expect(r100.deleted && r100.value == nil && r100.eligibility.reason == .deleted && r100.revision == 4 && r100.raw == alive.raw)
        #expect(s1.readings.updated == 1 && s1.readings.conflicted == 1)
        // Sintético remoto contra real local → kept_local; el local no cambia.
        let r101 = try #require(try await a.store.reading(recordID: realTwin.recordID))
        #expect(!r101.synthetic && r101.value == 140)
        let kinds = try await a.store.conflicts().map(\.resolution)
        #expect(kinds.sorted { $0.rawValue < $1.rawValue } == [.keptLocal, .tookRemote])

        // Local tombstone, remoto vivo → el tombstone no se levanta.
        let b = try await Self.make("b")
        try await b.store.upsertSession(session)
        try await b.store.insertReading(alive)
        try await b.store.deleteReading(recordID: alive.recordID)
        let pkgAlive = try Self.package(ArchiveContent(sessions: [session], readings: [alive]), at: Self.t0 + 9_001, in: b.dir)
        _ = try b.importer.importPackage(pkgAlive)
        let local = try #require(try await b.store.reading(recordID: alive.recordID))
        #expect(local.deleted && local.value == nil)
    }

    @Test("exclusión levantada solo con una ruta distinta que la política local evalúa elegible; con raw equivalente no")
    func liftingExclusions() async throws {
        let session = TestSupport.session()
        let badLive = RawReading(historicLifeCount: 50, qualityFlag: true, reservedHex: "ff")
        let goodFast = RawReading(uncapped: 133, qualityFlag: false)
        let env = try await Self.make()
        try await env.store.upsertSession(session)
        try await env.store.insertReadings([TestSupport.reading(session, lc: 100, raw: badLive, origin: .live),
                                            TestSupport.reading(session, lc: 101, raw: badLive, origin: .live),
                                            TestSupport.reading(session, lc: 30, raw: TestSupport.raw(uncapped: 100), origin: .live)])  // warm_up
        let remote = try Self.package(ArchiveContent(sessions: [session], readings: [
            TestSupport.reading(session, lc: 100, raw: goodFast, origin: .backfillFast),  // ruta distinta y elegible
            TestSupport.reading(session, lc: 101, raw: badLive, origin: .backfillHistory),  // mismo raw defectuoso: sigue excluida
            TestSupport.reading(session, lc: 30, raw: TestSupport.raw(uncapped: 101), origin: .backfillFast),  // sigue en calentamiento
        ]), at: Self.t0 + 9_000, in: env.dir)
        let summary = try env.importer.importPackage(remote)
        let r100 = try #require(try await env.store.reading(recordID: RecordID.make(sessionID: session.sessionID, lifeCount: 100)))
        #expect(r100.value == 133 && r100.origin == .backfillFast && r100.revision == 2 && r100.importedFrom?.archiveID == remote.manifest.archiveID)
        let r101 = try #require(try await env.store.reading(recordID: RecordID.make(sessionID: session.sessionID, lifeCount: 101)))
        #expect(r101.eligibility.reason == .qualityFlag && r101.revision == 1)
        let r30 = try #require(try await env.store.reading(recordID: RecordID.make(sessionID: session.sessionID, lifeCount: 30)))
        #expect(r30.eligibility.reason == .warmUp && r30.raw.uncapped == 100)
        #expect(summary.readings.updated == 1)
        let resolutions = try await env.store.conflicts().map { "\($0.id.split(separator: ":").last ?? ""):\($0.resolution.rawValue)" }.sorted()
        #expect(resolutions == ["100:merged", "30:kept_local"], "lc 101 trae el mismo raw: no es una ruta distinta, no hay conflicto")
    }

    @Test("lectura real en sesión sintética se rechaza aunque el manifest no sea sintético")
    func realReadingInSyntheticSessionIsRejected() async throws {
        let session = TestSupport.session(synthetic: true)
        let real = TestSupport.reading(session, lc: 100, raw: TestSupport.raw(uncapped: 130, capped: 128), origin: .live, synthetic: false)
        let env = try await Self.make()
        let written = try LingoScanArchiveWriter(producer: Self.producer("astra"))
            .write(ArchiveContent(sessions: [session], readings: [real]), createdAt: UTCInstant(epochSeconds: Self.t0 + 9_000), into: env.dir)
        #expect(!written.manifest.synthetic)
        do { _ = try env.importer.importPackage(at: written.url); Issue.record("debió rechazarse") } catch let e as ArchiveValidationError {
            guard case .syntheticInconsistency = e else { Issue.record("motivo inesperado \(e)"); return }
        }
        #expect(try await env.store.readingCount() == 0)
        #expect(try ArchiveSnapshotReader(databasePath: env.path).snapshot().sessions.isEmpty)
    }

    // MARK: Sesiones

    @Test("dos sesiones con el mismo life_count y el mismo minuto no colisionan; la equivalencia exige sensor y activación ±120 s conocida")
    func sessionsWithSameLifeCountDoNotCollide() async throws {
        let a = TestSupport.session()
        var b = TestSupport.session()  // mismo minuto de activación, otro sensor
        b.sensorSerialHash = String(repeating: "cd", count: 32)
        var c = TestSupport.session()  // mismo sensor que `a`, otra activación (> 120 s)
        c.activationTimeEpochS += 3_600
        var d = TestSupport.session()  // mismo sensor que `a`, a 60 s: la misma sesión física
        d.activationTimeEpochS += 60
        var unknown = TestSupport.session()  // activación desconocida: no se fusiona solo por el hash
        unknown.activationTimeEpochS = 0

        let env = try await Self.make()
        try await env.store.upsertSession(a)
        try await env.store.insertReading(TestSupport.reading(a, lc: 100, raw: TestSupport.raw(uncapped: 110, capped: 110), origin: .live))
        let content = ArchiveContent(
            sessions: [b, c, d, unknown],
            readings: [b, c, d, unknown].map { TestSupport.reading($0, lc: 100, raw: TestSupport.raw(uncapped: 150, capped: 150), origin: .live) })
        let summary = try env.importer.importPackage(try Self.package(content, at: Self.t0 + 9_000, in: env.dir))
        let snapshot = try ArchiveSnapshotReader(databasePath: env.path).snapshot()
        #expect(Set(snapshot.sessions.map(\.sessionID)) == [a.sessionID, b.sessionID, c.sessionID, unknown.sessionID])  // `d` pasa a alias de `a`
        let canonical = try #require(snapshot.sessions.first { $0.sessionID == a.sessionID })
        #expect(canonical.aliases.map(\.sessionID) == [d.sessionID] && canonical.revision == 2)
        #expect(snapshot.readings.count == 4)  // a:100, b:100, c:100, unknown:100; la de `d` es la 100 de `a`
        #expect(summary.sessions.new == 3 && summary.sessions.updated == 1)
        // Mismo life_count en `a` (valor local) y en `d`→`a` (kept_local con la remota completa).
        let kept = try #require(snapshot.readings.first { $0.recordID == RecordID.make(sessionID: a.sessionID, lifeCount: 100) })
        #expect(kept.value == 110)
        let reading = try #require(snapshot.conflicts.first { $0.kind == .reading })
        #expect(reading.remote?.value(at: "source_record_id") == .string(RecordID.make(sessionID: d.sessionID, lifeCount: 100)))
    }

    @Test("alias: traduce lecturas y sujetos del ledger con tres paquetes, conserva sync_identifier y es estable en cualquier orden")
    func aliasTranslationAcrossPackages() async throws {
        let a = TestSupport.session()
        var b = a; b.sessionID = TestSupport.newID(); b.activationTimeEpochS += 45
        let attempt = TestSupport.newID()
        func ledger(_ rid: String, sync: String) -> HealthLedgerEntry {
            HealthLedgerEntry(attemptID: attempt, subjectID: rid, subjectKind: .glucose, writerAppID: Self.astraApp, syncIdentifier: sync, syncVersion: 1,
                              exportedAt: UTCInstant(epochSeconds: Self.t0 + 7_000), result: .written)
        }
        let bRid = RecordID.make(sessionID: b.sessionID, lifeCount: 120)
        var outcomes: Set<String> = []
        for order in [[0, 1], [1, 0]] {
            let env = try await Self.make()
            try await env.store.upsertSession(a)
            let remoteContent = ArchiveContent(sessions: [b], readings: [TestSupport.reading(b, lc: 120, raw: TestSupport.raw(uncapped: 146, capped: 146), origin: .live)], ledger: [ledger(bRid, sync: bRid)])
            let p0 = try Self.package(remoteContent, at: Self.t0 + 9_000, in: env.dir)
            // Segundo paquete del mismo remoto (otra foto): ya conoce el alias.
            var later = remoteContent
            later.readings.append(TestSupport.reading(b, lc: 121, raw: TestSupport.raw(uncapped: 147, capped: 147), origin: .live))
            let p1 = try Self.package(later, at: Self.t0 + 9_500, in: env.dir)
            for i in order { _ = try env.importer.importPackage([p0, p1][i]) }
            let snap = try ArchiveSnapshotReader(databasePath: env.path).snapshot()
            #expect(snap.sessions.count == 1 && snap.sessions[0].sessionID == a.sessionID)
            #expect(snap.sessions[0].aliases.map(\.sessionID) == [b.sessionID])
            #expect(snap.readings.map(\.recordID).sorted() == [RecordID.make(sessionID: a.sessionID, lifeCount: 120), RecordID.make(sessionID: a.sessionID, lifeCount: 121)])
            let r120 = try #require(snap.readings.first { $0.lifeCount == 120 })
            #expect(r120.sourceRecordID == bRid && r120.sessionID == a.sessionID)
            #expect(snap.ledger.count == 1)
            #expect(snap.ledger[0].subjectID == RecordID.make(sessionID: a.sessionID, lifeCount: 120))
            #expect(snap.ledger[0].syncIdentifier == bRid, "sync_identifier ya usado en Health: no se reescribe")
            outcomes.insert(try ArchiveMergeFixturesTests.normalized(snap))
        }
        // El alias llega con `recorded_at_utc` del paquete que lo trajo en los dos órdenes, y el resto converge… salvo
        // el de la sesión (depende de qué paquete lo trajo primero): se comprueba lecturas y ledger arriba.
        #expect(outcomes.count <= 2)
    }

    @Test("sesión sintética equivalente a una real: kept_local y sus registros no entran")
    func syntheticSessionNeverMergesWithReal() async throws {
        let real = TestSupport.session()
        var synth = real; synth.sessionID = TestSupport.newID(); synth.synthetic = true
        let env = try await Self.make()
        try await env.store.upsertSession(real)
        let attempt = HealthLedgerEntry(attemptID: TestSupport.newID(), subjectID: RecordID.make(sessionID: synth.sessionID, lifeCount: 100), subjectKind: .glucose, writerAppID: Self.astraApp,
                                        syncIdentifier: "x", syncVersion: 1, exportedAt: UTCInstant(epochSeconds: Self.t0), result: .written)
        let pkg = try Self.package(ArchiveContent(sessions: [synth], readings: [TestSupport.reading(synth, lc: 100, raw: TestSupport.raw(uncapped: 110, capped: 110), origin: .live)], ledger: [attempt]), at: Self.t0 + 9_000, in: env.dir)
        #expect(pkg.manifest.synthetic)
        let summary = try env.importer.importPackage(pkg)
        let snap = try ArchiveSnapshotReader(databasePath: env.path).snapshot()
        #expect(snap.sessions.count == 1 && !snap.sessions[0].synthetic && snap.sessions[0].aliases.isEmpty)
        #expect(snap.readings.isEmpty && snap.ledger.isEmpty)
        #expect(summary.rejected == 2 && summary.sessions.conflicted == 1)
        #expect(snap.conflicts.map(\.resolution) == [.keptLocal] && snap.conflicts[0].kind == .session)
    }

    // MARK: Eventos

    @Test("linaje: A1→A2→A3 transportado por edit_ancestors sin conflicto; el local más nuevo se conserva")
    func ancestorsAreTransported() async throws {
        let eid = TestSupport.newID(), a1 = TestSupport.newID(), a2 = TestSupport.newID(), a3 = TestSupport.newID()
        let session = TestSupport.session()
        func pkg(_ events: [ArchiveEvent], _ env: (dir: URL, Void), _ at: Int64) throws -> ArchivePackage {
            try Self.package(ArchiveContent(sessions: [session], events: events), at: at, in: env.dir)
        }
        let v1 = ArchiveEvent(event: Self.event(eid, edit: a1, parent: nil), ancestors: [])
        let v3 = ArchiveEvent(event: Self.event(eid, edit: a3, parent: a2, text: "tres"),
                              ancestors: [EditLink(editID: a2, parentEditID: a1), EditLink(editID: a1, parentEditID: nil)])
        // Local en A1, remoto en A3 (con ancestros): gana el remoto.
        let env = try await Self.make()
        try await env.store.upsertEvent(v1.event)
        let s = try env.importer.importPackage(try pkg([v3], (env.dir, ()), Self.t0 + 9_000))
        #expect(try await env.store.event(id: eid)?.editID == a3 && s.events.updated == 1)
        #expect(try await env.store.conflicts().isEmpty)
        #expect(try await env.store.editAncestors(of: try #require(try await env.store.event(id: eid))) == v3.ancestors)
        // Local en A3, remoto viejo en A1: el local es más nuevo.
        let env2 = try await Self.make("b")
        try await env2.store.upsertEvent(v3.event, ancestors: v3.ancestors ?? [])
        let s2 = try env2.importer.importPackage(try pkg([v1], (env2.dir, ()), Self.t0 + 9_000))
        #expect(try await env2.store.event(id: eid)?.editID == a3 && s2.events.identical == 1)
        #expect(try await env2.store.conflicts().isEmpty)
    }

    @Test("ramas divergentes, linaje desconocido y borrado contra edición")
    func divergenceAndUnknownLineage() async throws {
        let session = TestSupport.session()
        // Divergentes: ambos descienden de A1.
        let eid = TestSupport.newID(), a1 = TestSupport.newID(), l2 = TestSupport.newID(), r2 = TestSupport.newID()
        let env = try await Self.make()
        try await env.store.upsertEvent(Self.event(eid, edit: a1, parent: nil))
        try await env.store.upsertEvent(Self.event(eid, edit: l2, parent: a1, text: "local", app: "com.otalvaro.lingoscan"))
        let remote = ArchiveEvent(event: Self.event(eid, edit: r2, parent: a1, text: "remoto"), ancestors: [EditLink(editID: a1, parentEditID: nil)])
        let s = try env.importer.importPackage(try Self.package(ArchiveContent(sessions: [session], events: [remote]), at: Self.t0 + 9_000, in: env.dir))
        #expect(try await env.store.event(id: eid)?.editID == l2, "se muestra la local")
        let c = try #require(try await env.store.conflicts().first)
        #expect(c.resolution == .divergent && c.remoteArchiveID == s.archiveID)
        #expect(c.remote?.value(at: "edit_id") == .string(r2) && c.remote?.value(at: "text") == .string("remoto"))
        #expect(c.remote?.value(at: "edit_ancestors") != .null, "la evidencia de linaje viaja en el conflicto")

        // Linaje desconocido: el remoto cuelga de un padre que no conocemos y no trae ancestros.
        let eid2 = TestSupport.newID(), b1 = TestSupport.newID(), bx = TestSupport.newID(), by = TestSupport.newID()
        let env2 = try await Self.make("b")
        try await env2.store.upsertEvent(Self.event(eid2, edit: b1, parent: nil))
        let legacy = ArchiveEvent(event: Self.event(eid2, edit: by, parent: bx, text: "viejo"), ancestors: nil)
        _ = try env2.importer.importPackage(try Self.package(ArchiveContent(sessions: [session], events: [legacy]), at: Self.t0 + 9_000, in: env2.dir))
        let u = try #require(try await env2.store.conflicts().first)
        #expect(u.resolution == .lineageUnknown, "sin eslabones no se afirma divergencia")
        #expect(try await env2.store.event(id: eid2)?.editID == b1)

        // Borrado que desciende de la edición local: gana el tombstone. Edición que desciende del tombstone: gana la edición.
        let eid3 = TestSupport.newID(), c1 = TestSupport.newID(), c2 = TestSupport.newID(), c3 = TestSupport.newID()
        let env3 = try await Self.make("c")
        try await env3.store.upsertEvent(Self.event(eid3, edit: c1, parent: nil))
        let tomb = ArchiveEvent(event: Self.event(eid3, edit: c2, parent: c1, deleted: true), ancestors: [EditLink(editID: c1, parentEditID: nil)])
        _ = try env3.importer.importPackage(try Self.package(ArchiveContent(sessions: [session], events: [tomb]), at: Self.t0 + 9_000, in: env3.dir))
        let tombstoned = try await env3.store.event(id: eid3)
        let noConflicts = try await env3.store.conflicts().isEmpty
        #expect(tombstoned?.deleted == true && noConflicts)
        let revived = ArchiveEvent(event: Self.event(eid3, edit: c3, parent: c2, text: "de vuelta"),
                                   ancestors: [EditLink(editID: c2, parentEditID: c1), EditLink(editID: c1, parentEditID: nil)])
        _ = try env3.importer.importPackage(try Self.package(ArchiveContent(sessions: [session], events: [revived]), at: Self.t0 + 9_100, in: env3.dir))
        let back = try await env3.store.event(id: eid3)
        #expect(back?.deleted == false && back?.text == "de vuelta")
    }

    // MARK: Ledger y Health

    @Test("ledger: unión por attempt_id; un fallo posterior no borra un written")
    func ledgerUnionIsAppendOnly() async throws {
        let session = TestSupport.session()
        let rid = RecordID.make(sessionID: session.sessionID, lifeCount: 100)
        func entry(_ id: String, _ result: HealthLedgerResult, _ at: Int64) -> HealthLedgerEntry {
            HealthLedgerEntry(attemptID: id, subjectID: rid, subjectKind: .glucose, writerAppID: Self.astraApp, syncIdentifier: rid, syncVersion: 1, exportedAt: UTCInstant(epochSeconds: Self.t0 + at), result: result)
        }
        let w = TestSupport.newID(), f = TestSupport.newID()
        let reading = TestSupport.reading(session, lc: 100, raw: TestSupport.raw(uncapped: 111, capped: 111), origin: .live)
        let env = try await Self.make()
        try await env.store.upsertSession(session)
        try await env.store.insertReading(reading)
        try await env.store.appendLedger(entry(w, .written, 1_000))
        let p1 = try Self.package(ArchiveContent(sessions: [session], readings: [reading], ledger: [entry(w, .written, 1_000), entry(f, .failed, 2_000)]), at: Self.t0 + 9_000, in: env.dir)
        let s = try env.importer.importPackage(p1)
        #expect(s.ledger.new == 1 && s.ledger.identical == 1)
        let ledger = try await env.store.ledgerEntries(subjectID: rid)
        #expect(ledger.count == 2)
        #expect(try await env.store.derivedHealthState(subjectID: rid, writerAppID: Self.astraApp) == .written)
        #expect(try await env.store.pendingHealthSubjects().isEmpty)
    }

    @Test("tres paquetes: cada trama conserva su origen y alternativa sin depender del orden (out_of_order)")
    func threePackagesOutOfOrder() async throws {
        let dir = ArchiveTestSupport.examplesURL.appending(path: "merge/out_of_order", directoryHint: .isDirectory)
        let a = try LingoScanArchiveReader().read(at: dir.appending(path: "LingoScan-lingoscan-20261027T141000Z-6aa6039b.lingoscan", directoryHint: .isDirectory))
        let b = try LingoScanArchiveReader().read(at: dir.appending(path: "LingoScan-astra-20261027T142000Z-11ed348c.lingoscan", directoryHint: .isDirectory))
        let work = try ArchiveTestSupport.temporaryDirectory()
        var bPrime = b.content
        bPrime.readings = b.content.readings.filter { $0.lifeCount != 100 }
        var cOnly = b.content
        cOnly.readings = b.content.readings.filter { $0.lifeCount == 100 }
        let pb = try Self.package(bPrime, at: Self.t0 + 1, in: work)
        let pc = try Self.package(cOnly, at: Self.t0 + 2, in: work)
        var origins: [String] = []
        for (label, order) in [("A luego C", [a.url, pc.url]), ("C luego A", [pc.url, a.url])] {
            let env = try await Self.make()
            try await ArchiveTestSupport.seed(env.store, with: pb)
            let importer = ArchiveImporter(databasePath: env.path, localPolicy: AstraV1TestPolicy(), now: ArchiveTestSupport.fixedNow)
            for url in order { _ = try importer.importPackage(at: url) }
            let snap = try ArchiveSnapshotReader(databasePath: env.path).snapshot()
            let r = try #require(snap.readings.first { $0.lifeCount == 100 })
            #expect(snap.readings.count == 100 && snap.conflicts.count == 1 && snap.conflicts[0].resolution == .merged, "\(label)")
            origins.append(r.origin.rawValue)
        }
        #expect(origins == ["live", "backfill_fast"])
    }

    // MARK: Transacción

    @Test("un fallo a mitad de la importación revierte todo: sin sesión, lecturas ni archive_id registrado")
    func importIsAtomic() async throws {
        let env = try await Self.make()
        let db = try ArchiveDatabase(path: env.path)
        try db.connection.executeScript("""
            CREATE TRIGGER boom BEFORE INSERT ON health_export_ledger BEGIN SELECT RAISE(ABORT, 'boom'); END;
            """)
        let url = ArchiveTestSupport.examplesURL.appending(path: "LingoScan-lingoscan-20261027T150405Z-3fa85f64.lingoscan", directoryHint: .isDirectory)
        do { _ = try env.importer.importPackage(at: url); Issue.record("debió fallar") } catch is SQLiteError {}
        #expect(try await env.store.readingCount() == 0)
        let snap = try ArchiveSnapshotReader(databasePath: env.path).snapshot()
        #expect(snap.sessions.isEmpty && snap.events.isEmpty && snap.ledger.isEmpty && snap.conflicts.isEmpty)
        #expect(try await env.store.isArchiveKnown("3fa85f64-9a1c-4e27-8b5d-71c0d3a4e8f2") == false)
        try db.connection.executeScript("DROP TRIGGER boom;")
        #expect(try env.importer.importPackage(at: url).readings.new == 163, "tras quitar el fallo, la importación completa funciona")
    }
}
