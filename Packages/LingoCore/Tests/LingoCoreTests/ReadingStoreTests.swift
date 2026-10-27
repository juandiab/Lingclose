import Foundation
import Testing
@testable import LingoCore

struct ReadingStoreTests {
    private func setUp(synthetic: Bool = false) async throws -> (SQLiteStore, SensorSessionRecord) {
        let store = try TestSupport.makeStore()
        let session = TestSupport.session(synthetic: synthetic)
        try await store.upsertSession(session)
        return (store, session)
    }

    @Test func sessionRoundTripAndLookupBySerialHash() async throws {
        let (store, session) = try await setUp()
        #expect(try await store.session(byID: session.sessionID) == session)
        #expect(try await store.sessions(bySerialHash: session.sensorSerialHash) == [session])
        #expect(try await store.sessions(bySerialHash: String(repeating: "cd", count: 32)).isEmpty)
        var updated = session
        updated.lastLifeCount = 99
        updated.revision = 2
        updated.aliases = [SessionAlias(sessionID: TestSupport.newID(), appID: "com.otalvaro.lingoscan.astra",
                                        archiveID: TestSupport.newID(), recordedAt: UTCInstant(epochSeconds: 1))]
        try await store.upsertSession(updated)
        #expect(try await store.session(byID: session.sessionID) == updated)
    }

    @Test func insertingThreeTimesIsIdempotent() async throws {
        let (store, session) = try await setUp()
        let r = TestSupport.reading(session, lc: 100, raw: TestSupport.raw(uncapped: 150, trend: 3), origin: .live)
        var outcomes: [ReadingInsertOutcome] = []
        for _ in 0..<3 { outcomes.append(try await store.insertReading(r)) }
        #expect(outcomes == [.inserted, .unchanged, .unchanged])
        #expect(try await store.readingCount() == 1)
        #expect(try await store.reading(recordID: r.recordID) == r)
        #expect(try await store.conflicts().isEmpty)
        // También en lote.
        #expect(try await store.insertReadings([r, r, r]) == [.unchanged, .unchanged, .unchanged])
    }

    @Test func liveWinsOverLaterBackfillAndComplementaryRawIsKept() async throws {
        let (store, session) = try await setUp()
        let live = TestSupport.reading(session, lc: 200, raw: TestSupport.raw(uncapped: 150, capped: 150, trend: 3), origin: .live)
        let fast = TestSupport.reading(session, lc: 200, raw: TestSupport.raw(uncapped: 151), origin: .backfillFast)
        #expect(try await store.insertReading(live) == .inserted)
        #expect(try await store.insertReading(fast) == .keptExisting)
        #expect(try await store.insertReading(fast) == .keptExisting)  // sin conflicto duplicado
        let stored = try #require(try await store.reading(recordID: live.recordID))
        #expect(stored.origin == .live && stored.value == 150 && stored.revision == 1)
        let conflicts = try await store.conflicts(id: live.recordID)
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.resolution == .keptLocal)
        let remote = try #require(conflicts.first?.remote).decoded(as: GlucoseReading.self)
        #expect(remote.origin == .backfillFast && remote.raw.uncapped == 151)
    }

    @Test func liveArrivingAfterBackfillReplacesItWithItsOwnBytes() async throws {
        let (store, session) = try await setUp()
        let history = TestSupport.reading(session, lc: 300, raw: TestSupport.raw(capped: 120), origin: .backfillHistory)
        let live = TestSupport.reading(session, lc: 300, raw: TestSupport.raw(uncapped: 122, capped: 120, trend: 4), origin: .live)
        #expect(try await store.insertReading(history) == .inserted)
        #expect(try await store.insertReading(live) == .replaced)
        let stored = try #require(try await store.reading(recordID: live.recordID))
        #expect(stored.origin == .live && stored.raw == live.raw && stored.value == 122 && stored.revision == 2)
        #expect(try await store.conflicts(id: live.recordID).map(\.resolution) == [.merged])
        // Repetir el live no cambia nada.
        var again = live
        again.revision = 1
        #expect(try await store.insertReading(again) == .unchanged)
    }

    @Test func identicalRawFromHigherPrecedenceRouteOnlyUpgradesOrigin() async throws {
        let (store, session) = try await setUp()
        let raw = TestSupport.raw(uncapped: 140)
        let embedded = TestSupport.reading(session, lc: 400, raw: raw, origin: .embeddedHistory)
        let fast = TestSupport.reading(session, lc: 400, raw: raw, origin: .backfillFast)
        #expect(try await store.insertReading(fast) == .inserted)
        #expect(try await store.insertReading(embedded) == .unchanged)
        let live = TestSupport.reading(session, lc: 400, raw: raw, origin: .live)
        #expect(try await store.insertReading(live) == .originUpgraded)
        let stored = try #require(try await store.reading(recordID: live.recordID))
        #expect(stored.origin == .live && stored.revision == 2)
        #expect(try await store.conflicts().isEmpty)
    }

    @Test func qualityFlagExclusionIsLiftedByDistinctRoute() async throws {
        let (store, session) = try await setUp()
        let live = TestSupport.reading(session, lc: 500, raw: TestSupport.raw(qualityFlag: true, trend: 0, channel: 1), origin: .live)
        let fast = TestSupport.reading(session, lc: 500, raw: TestSupport.raw(uncapped: 140), origin: .backfillFast)
        #expect(live.eligibility.reason == .qualityFlag && fast.eligibility.isEligible)
        #expect(try await store.insertReading(live) == .inserted)
        #expect(try await store.insertReading(fast) == .exclusionLifted)
        let stored = try #require(try await store.reading(recordID: live.recordID))
        #expect(stored.origin == .backfillFast && stored.eligibility.isEligible && stored.value == 140 && stored.revision == 2)
        let conflict = try #require(try await store.conflicts(id: live.recordID).first)
        #expect(conflict.resolution == .merged)
        #expect(try #require(conflict.local).decoded(as: GlucoseReading.self).raw == live.raw)
    }

    @Test func equivalentRawNeverLiftsAnExclusion() async throws {
        let (store, session) = try await setUp()
        // live con bit 15 seguido de backfill_history con el mismo bit 15: sigue excluido.
        let live = TestSupport.reading(session, lc: 600, raw: TestSupport.raw(qualityFlag: true, trend: 0), origin: .live)
        let history = TestSupport.reading(session, lc: 600, raw: TestSupport.raw(qualityFlag: true), origin: .backfillHistory)
        #expect(live.raw.isEquivalent(to: history.raw))
        try await store.insertReading(live)
        #expect(try await store.insertReading(history) == .keptExisting)
        #expect(try await store.reading(recordID: live.recordID)?.eligibility.reason == .qualityFlag)

        // Excluida por warm-up; el mismo raw por otra ruta evaluado como elegible (otra política) no levanta nada:
        // sería solo una diferencia de política.
        let warm = TestSupport.reading(session, lc: 30, raw: TestSupport.raw(uncapped: 100), origin: .live)
        #expect(warm.eligibility.reason == .warmUp)
        var samePolicyDifference = TestSupport.reading(session, lc: 30, raw: TestSupport.raw(uncapped: 100, trend: 3), origin: .backfillFast)
        samePolicyDifference.eligibility = .eligible(policyID: "otra", policyVersion: "1")
        samePolicyDifference.value = 100
        #expect(warm.raw.isEquivalent(to: samePolicyDifference.raw))
        try await store.insertReading(warm)
        #expect(try await store.insertReading(samePolicyDifference) == .keptExisting)
        #expect(try await store.reading(recordID: warm.recordID)?.eligibility.reason == .warmUp)
    }

    @Test func eligibleReadingIsNeverDowngradedByHigherPrecedenceExcludedRoute() async throws {
        let (store, session) = try await setUp()
        let fast = TestSupport.reading(session, lc: 700, raw: TestSupport.raw(uncapped: 140), origin: .backfillFast)
        let live = TestSupport.reading(session, lc: 700, raw: TestSupport.raw(qualityFlag: true), origin: .live)
        try await store.insertReading(fast)
        #expect(try await store.insertReading(live) == .keptExisting)
        #expect(try await store.reading(recordID: fast.recordID)?.origin == .backfillFast)
    }

    @Test func realReadingInSyntheticSessionIsRejected() async throws {
        let (store, session) = try await setUp(synthetic: true)
        let synthetic = TestSupport.reading(session, lc: 100, raw: TestSupport.raw(uncapped: 120), origin: .live)
        #expect(synthetic.synthetic)
        #expect(try await store.insertReading(synthetic) == .inserted)
        let real = TestSupport.reading(session, lc: 101, raw: TestSupport.raw(uncapped: 120), origin: .live, synthetic: false)
        await #expect(throws: StoreError.realReadingInSyntheticSession(recordID: real.recordID, sessionID: session.sessionID)) {
            try await store.insertReading(real)
        }
        #expect(try await store.reading(recordID: real.recordID) == nil)
        // Un lote con una lectura real se rechaza entero.
        let more = TestSupport.reading(session, lc: 102, raw: TestSupport.raw(uncapped: 120), origin: .live)
        await #expect(throws: StoreError.self) { try await store.insertReadings([more, real]) }
        #expect(try await store.reading(recordID: more.recordID) == nil)
        // La sesión sintética no puede volverse real.
        var flipped = session
        flipped.synthetic = false
        await #expect(throws: StoreError.syntheticSessionCannotBecomeReal(sessionID: session.sessionID)) {
            try await store.upsertSession(flipped)
        }
    }

    @Test func tombstonesAreSticky() async throws {
        let (store, session) = try await setUp()
        let r = TestSupport.reading(session, lc: 800, raw: TestSupport.raw(uncapped: 130), origin: .backfillFast)
        try await store.insertReading(r)
        try await store.deleteReading(recordID: r.recordID)
        let deleted = try #require(try await store.reading(recordID: r.recordID))
        #expect(deleted.deleted && deleted.value == nil && deleted.eligibility.reason == .deleted && deleted.revision == 2)
        let live = TestSupport.reading(session, lc: 800, raw: TestSupport.raw(uncapped: 131), origin: .live)
        #expect(try await store.insertReading(live) == .unchanged)
        #expect(try await store.readings(in: r.measuredAt...r.measuredAt).isEmpty)
        #expect(try await store.readings(in: r.measuredAt...r.measuredAt, includeDeleted: true).count == 1)
    }

    @Test func rangeQueriesAndLiveRegressionLog() async throws {
        let (store, session) = try await setUp()
        let batch = (90..<110).map { TestSupport.reading(session, lc: $0, raw: TestSupport.raw(uncapped: 100 + $0), origin: .live) }
        try await store.insertReadings(batch)
        let byLC = try await store.readings(sessionID: session.sessionID, lifeCountRange: 95...99)
        #expect(byLC.map(\.lifeCount) == [95, 96, 97, 98, 99])
        let from = MeasuredAt.compute(activationEpoch: session.activationTimeEpochS, lifeCount: 100)
        let to = MeasuredAt.compute(activationEpoch: session.activationTimeEpochS, lifeCount: 104)
        #expect(try await store.readings(in: from...to).map(\.lifeCount) == [100, 101, 102, 103, 104])

        let late = TestSupport.reading(session, lc: 50, raw: TestSupport.raw(uncapped: 100), origin: .live)
        try await store.insertReading(late)
        let log = try await store.recentLogEvents()
        #expect(log.contains { $0.category == "live_life_count_regression" && $0.level == .warning })
        // Un backfill antiguo es normal y no genera diagnóstico (C2).
        let old = TestSupport.reading(session, lc: 40, raw: TestSupport.raw(uncapped: 100), origin: .backfillHistory)
        try await store.insertReading(old)
        #expect(try await store.recentLogEvents().filter { $0.category == "live_life_count_regression" }.count == 1)
    }
}
