import Foundation
import Testing
import LingoCore
@testable import LingoScan

struct HealthExporterTests {
    private let writer = HealthExporter.writerAppID

    private struct Rig {
        let store: SQLiteStore
        let sink: InMemoryHealthSink
        let clock: HealthTestClock
        let policy: HealthPolicyBox
        let exporter: HealthExporter
        let session: SensorSessionRecord
    }

    private func rig(readings: Int = 0, firstLifeCount: Int = 100, batchSize: Int = 100) async throws -> Rig {
        let store = try HealthFixtures.makeStore()
        let session = HealthFixtures.session()
        try await store.upsertSession(session)
        if readings > 0 {
            try await store.insertReadings((0..<readings).map { HealthFixtures.reading(session, lifeCount: firstLifeCount + $0) })
        }
        let sink = InMemoryHealthSink()
        let clock = HealthTestClock()
        let policy = HealthPolicyBox()
        let exporter = HealthExporter(
            store: store, sink: sink, policy: { policy.policy }, now: { clock.now },
            backoff: HealthBackoff(baseSeconds: 60, maxSeconds: 3600), batchSize: batchSize)
        return Rig(store: store, sink: sink, clock: clock, policy: policy, exporter: exporter, session: session)
    }

    @Test func hundredEligibleReadingsBecomeHundredSamplesWithSyncIdentifier() async throws {
        let r = try await rig(readings: 100, batchSize: 30)
        let summary = await r.exporter.drain()
        #expect(summary.written == 100)
        let samples = await r.sink.samples
        #expect(samples.count == 100)
        let ids = Set(try await r.store.readings(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 3_000_000_000)).map(\.recordID))
        #expect(Set(samples.keys) == ids)
        for (id, spec) in samples {
            #expect(spec.syncIdentifier == id && spec.kind == .glucose && spec.unit == .milligramsPerDeciliter)
            #expect(spec.wasUserEntered == false && spec.sessionID == r.session.sessionID && spec.origin == "live")
        }
        #expect(await r.exporter.pendingCount == 0)
        #expect(await r.exporter.lastError == nil)
        for id in ids {
            #expect(try await r.store.derivedHealthState(subjectID: id, writerAppID: writer) == .written)
        }
    }

    @Test func retryDoesNotDuplicate() async throws {
        let r = try await rig(readings: 10)
        await r.exporter.drain()
        let second = await r.exporter.drain()
        #expect(second.written == 0)
        #expect(await r.sink.samples.count == 10)
        #expect(await r.sink.attemptedIdentifiers.count == 10)
        #expect(await r.sink.writeCalls == 1)
    }

    @Test func qualityFlagSyntheticAndTombstonesNeverReachTheSink() async throws {
        let r = try await rig(readings: 3)
        let good = try await r.store.readings(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 3_000_000_000))
        // Calidad dudosa (bit 15), fuera de rango y calentamiento: guardados pero no elegibles.
        try await r.store.insertReadings([
            HealthFixtures.reading(r.session, lifeCount: 200, qualityFlag: true),
            HealthFixtures.reading(r.session, lifeCount: 201, value: 20),
            HealthFixtures.reading(r.session, lifeCount: 5),
        ])
        // Tombstone de una lectura buena.
        let deleted = good[0]
        try await r.store.deleteReading(recordID: deleted.recordID)
        // Sesión sintética completa.
        let fixture = HealthFixtures.session(synthetic: true)
        try await r.store.upsertSession(fixture)
        try await r.store.insertReadings([HealthFixtures.reading(fixture, lifeCount: 100)])
        // Eventos: nota, ejercicio, comida sintética, comida sin carbohidratos.
        for e in [HealthFixtures.meal(kind: .note), HealthFixtures.meal(kind: .exercise),
                  HealthFixtures.meal(synthetic: true), HealthFixtures.meal(carbs: nil)] {
            try await r.store.upsertEvent(e)
        }
        await r.exporter.drain()
        let sent = Set(await r.sink.samples.keys)
        #expect(sent == Set(good.dropFirst().map(\.recordID)))
        #expect(await r.exporter.pendingCount == 0)
    }

    @Test func syntheticReadingCannotBeBuiltAsExportable() throws {
        // Es lo que impide al exportador recibir sintéticos: no existe otro camino hacia `HealthSampleMapper.spec(for:)`.
        let fixture = HealthFixtures.session(synthetic: true)
        let reading = HealthFixtures.reading(fixture, lifeCount: 100)
        #expect(reading.synthetic)
        #expect(HealthExportable(reading: reading) == nil)
        #expect(HealthExportable(reading: reading, session: fixture) == nil)
    }

    @Test func failedThenWrittenLeavesDerivedStateWritten() async throws {
        let r = try await rig(readings: 2)
        let all = try await r.store.readings(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 3_000_000_000))
        let bad = all[0], ok = all[1]
        await r.sink.setFailing([bad.recordID])
        let first = await r.exporter.drain()
        #expect(first.written == 1 && first.failed == 1)
        #expect(await r.exporter.lastError != nil)
        #expect(try await r.store.derivedHealthState(subjectID: bad.recordID, writerAppID: writer) == .failed)
        #expect(await r.exporter.pendingCount == 1)

        // Dentro de la espera no reintenta.
        let early = await r.exporter.drain()
        #expect(early.deferredByBackoff == 1 && early.written == 0)

        await r.sink.setFailing([])
        r.clock.advance(seconds: 61)
        let retry = await r.exporter.drain()
        #expect(retry.written == 1)
        #expect(try await r.store.derivedHealthState(subjectID: bad.recordID, writerAppID: writer) == .written)
        #expect(try await r.store.ledgerEntries(subjectID: bad.recordID).map(\.result) == [.failed, .written])
        #expect(try await r.store.derivedHealthState(subjectID: ok.recordID, writerAppID: writer) == .written)
        #expect(await r.exporter.lastError == nil)
        #expect(await r.sink.samples.count == 2)
    }

    @Test func backoffGrowsWithConsecutiveFailures() async throws {
        let r = try await rig(readings: 1)
        let id = try await r.store.readings(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 3_000_000_000))[0].recordID
        await r.sink.setFailing([id])
        await r.exporter.drain()           // fallo 1 → espera 60 s
        r.clock.advance(seconds: 61)
        await r.exporter.drain()           // fallo 2 → espera 120 s
        r.clock.advance(seconds: 61)
        #expect(await r.exporter.drain().deferredByBackoff == 1)
        r.clock.advance(seconds: 60)
        #expect(await r.exporter.drain().failed == 1)
        #expect(try await r.store.ledgerEntries(subjectID: id).count == 3)
        // Una acción explícita ignora la espera.
        #expect(await r.exporter.drain(force: true).failed == 1)
    }

    @Test func unknownReconcilesWithoutRewriting() async throws {
        let r = try await rig(readings: 2)
        let all = try await r.store.readings(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 3_000_000_000))
        let lost = all[0], missing = all[1]
        for s in all {
            try await r.store.appendLedger(HealthLedgerEntry(
                attemptID: UUID().uuidString, subjectID: s.recordID, subjectKind: .glucose, writerAppID: writer,
                syncIdentifier: s.recordID, syncVersion: s.revision, exportedAt: UTCInstant(r.clock.now), result: .unknown))
        }
        // `lost` sí llegó a Health; `missing` no.
        let exportable = try #require(HealthExportable(reading: lost, session: r.session))
        await r.sink.preload(HealthSampleMapper.spec(for: exportable))
        let summary = await r.exporter.drain()
        #expect(summary.reconciled == 1 && summary.written == 1)
        #expect(await r.sink.attemptedIdentifiers == [missing.recordID])
        #expect(try await r.store.ledgerEntries(subjectID: lost.recordID).map(\.result) == [.unknown, .written])
        #expect(try await r.store.derivedHealthState(subjectID: lost.recordID, writerAppID: writer) == .written)
        #expect(try await r.store.derivedHealthState(subjectID: missing.recordID, writerAppID: writer) == .written)
    }

    @Test func failedReconciliationQueryWritesNothingForThoseSubjects() async throws {
        let r = try await rig(readings: 1)
        let s = try await r.store.readings(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 3_000_000_000))[0]
        try await r.store.appendLedger(HealthLedgerEntry(
            attemptID: UUID().uuidString, subjectID: s.recordID, subjectKind: .glucose, writerAppID: writer,
            syncIdentifier: s.recordID, syncVersion: s.revision, exportedAt: UTCInstant(r.clock.now), result: .unknown))
        await r.sink.setQueryError(.failed("simulado"))
        await r.exporter.drain()
        #expect(await r.sink.attemptedIdentifiers.isEmpty)
        #expect(try await r.store.derivedHealthState(subjectID: s.recordID, writerAppID: writer) == .unknown)
        #expect(await r.exporter.lastError != nil)
    }

    @Test func handoverIsRespectedAndFillGapsOverridesIt() async throws {
        let r = try await rig(readings: 10)
        let all = try await r.store.readings(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 3_000_000_000))
        let handover = all[4].measuredAt
        r.policy.policy = HealthExportPolicy(handoverAt: handover)
        let first = await r.exporter.drain()
        #expect(first.written == 5 && first.heldByHandover == 5)
        #expect(Set(await r.sink.samples.keys) == Set(all[5...].map(\.recordID)))
        #expect(await r.exporter.pendingCount == 5)  // los huecos siguen visibles como pendientes
        r.policy.policy = HealthExportPolicy(handoverAt: handover, fillGaps: true)
        let fill = await r.exporter.drain()
        #expect(fill.written == 5)
        #expect(await r.sink.samples.count == 10)
        #expect(await r.exporter.pendingCount == 0)
    }

    @Test func pausedWritesNothingAndTouchesNoLedger() async throws {
        let r = try await rig(readings: 5)
        r.policy.policy = HealthExportPolicy(isPaused: true)
        let summary = await r.exporter.drain()
        #expect(summary.paused && summary.written == 0)
        #expect(await r.sink.writeCalls == 0)
        #expect(await r.exporter.pendingCount == 5)
        r.policy.policy = .active
        #expect(await r.exporter.drain().written == 5)
    }

    @Test func deniedPermissionLeavesOutboxAndLedgerIntact() async throws {
        let r = try await rig(readings: 5)
        await r.sink.setStatus(.denied)
        let summary = await r.exporter.drain()
        #expect(summary.stoppedByError && summary.written == 0)
        #expect(await r.exporter.isAuthorized == false)
        #expect(await r.exporter.lastError != nil)
        #expect(await r.exporter.pendingCount == 5)
        let id = try await r.store.pendingHealthSubjects()[0].subjectID
        #expect(try await r.store.ledgerEntries(subjectID: id).isEmpty)
        // También si Health rechaza en el momento de escribir.
        await r.sink.setStatus(.authorized)
        await r.sink.setWriteError(.authorizationDenied)
        let second = await r.exporter.drain()
        #expect(second.stoppedByError)
        #expect(try await r.store.ledgerEntries(subjectID: id).isEmpty)
        #expect(await r.exporter.isAuthorized == false)
        // Al volver el permiso, se drena.
        await r.sink.setWriteError(nil)
        #expect(await r.exporter.drain().written == 5)
        #expect(await r.exporter.isAuthorized)
    }

    @Test func unavailableHealthKitReportsTypedErrorWithoutCrashing() async throws {
        let r = try await rig(readings: 2)
        await r.sink.setStatus(.unavailable)
        let summary = await r.exporter.drain()
        #expect(summary.stoppedByError)
        #expect(await r.exporter.lastError == HealthSinkError.unavailable.description)
        #expect(await r.exporter.pendingCount == 2)
    }

    @Test func requestAuthorizationUpdatesFlag() async throws {
        let r = try await rig()
        await r.sink.setStatus(.notDetermined)
        await r.exporter.requestAuthorization()
        #expect(await r.exporter.isAuthorized)
    }

    @Test func mealCarbsGoOutWithNoteAndOnlyOnce() async throws {
        let r = try await rig()
        let meal = HealthFixtures.meal(carbs: 45, text: "arepa con huevo")
        try await r.store.upsertEvent(meal)
        try await r.store.upsertEvent(HealthFixtures.meal(kind: .note))
        let summary = await r.exporter.drain()
        #expect(summary.written == 1)
        let spec = try #require(await r.sink.samples[meal.eventID])
        #expect(spec.kind == .carbs && spec.unit == .grams && spec.value == 45)
        #expect(spec.note == "arepa con huevo" && spec.wasUserEntered == false)
        #expect(spec.date == meal.at && spec.syncVersion == meal.revision)
        let entries = try await r.store.ledgerEntries(subjectID: meal.eventID)
        #expect(entries.count == 1 && entries[0].subjectKind == .carbs && entries[0].writerAppID == writer)
        await r.exporter.drain()
        #expect(await r.sink.attemptedIdentifiers == [meal.eventID])
    }

    @Test func ledgerEntriesCarryAttemptIDsAndWriter() async throws {
        let r = try await rig(readings: 3)
        await r.exporter.drain()
        var attempts: Set<String> = []
        for s in try await r.store.readings(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 3_000_000_000)) {
            let e = try await r.store.ledgerEntries(subjectID: s.recordID)
            #expect(e.count == 1 && e[0].writerAppID == "com.otalvaro.lingoscan" && e[0].syncVersion == s.revision)
            attempts.insert(e[0].attemptID)
        }
        #expect(attempts.count == 3)
    }

    @Test func workoutsAreReadByRange() async throws {
        let r = try await rig()
        let w = HealthWorkoutSummary(id: "w1", start: UTCInstant(epochSeconds: 100), end: UTCInstant(epochSeconds: 200),
                                     activityTypeRaw: 37, sourceName: "Test")
        await r.sink.setWorkouts([w])
        #expect(try await r.exporter.workouts(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 150)) == [w])
        #expect(try await r.exporter.workouts(in: UTCInstant(epochSeconds: 300)...UTCInstant(epochSeconds: 400)).isEmpty)
    }
}
