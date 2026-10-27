import Testing
@testable import LingoCore

struct HealthPlanTests {
    private func subject(_ id: String, at: Int64, kind: HealthSubjectKind = .glucose) -> PendingHealthSubject {
        PendingHealthSubject(subjectID: id, subjectKind: kind, measuredAt: UTCInstant(epochSeconds: at))
    }

    private func candidate(_ id: String, at: Int64, _ state: DerivedHealthState, last: Int64? = nil, fails: Int = 0)
        -> HealthExportPlan.Candidate {
        .init(subject: subject(id, at: at), state: state, lastAttemptAt: last.map { UTCInstant(epochSeconds: $0) },
              consecutiveFailures: fails)
    }

    @Test func backoffDoublesAndCaps() {
        let b = HealthBackoff(baseSeconds: 60, maxSeconds: 600)
        #expect([0, 1, 2, 3, 4, 5, 99].map { b.delay(consecutiveFailures: $0) } == [0, 60, 120, 240, 480, 600, 600])
    }

    @Test func pausedPlansNothing() {
        let plan = HealthExportPlan.make(candidates: [candidate("a", at: 10, .none), candidate("b", at: 11, .unknown)],
                                         policy: HealthExportPolicy(isPaused: true), now: UTCInstant(epochSeconds: 100),
                                         backoff: .default)
        #expect(plan.write.isEmpty && plan.reconcile.isEmpty && plan.heldByHandover.isEmpty)
    }

    @Test func handoverHoldsOlderSubjectsUnlessFillingGaps() {
        let cs = [candidate("old", at: 100, .none), candidate("edge", at: 200, .none), candidate("new", at: 201, .none)]
        let now = UTCInstant(epochSeconds: 1000)
        let held = HealthExportPlan.make(candidates: cs, policy: HealthExportPolicy(handoverAt: UTCInstant(epochSeconds: 200)),
                                         now: now, backoff: .default)
        #expect(held.write.map(\.subjectID) == ["new"])
        #expect(held.heldByHandover.map(\.subjectID) == ["old", "edge"])
        let fill = HealthExportPlan.make(candidates: cs, policy: HealthExportPolicy(handoverAt: UTCInstant(epochSeconds: 200), fillGaps: true),
                                         now: now, backoff: .default)
        #expect(fill.write.map(\.subjectID) == ["old", "edge", "new"])
    }

    @Test func failedWaitsForBackoffAndForceOverrides() {
        let cs = [candidate("f", at: 10, .failed, last: 1000, fails: 2)]  // espera 120 s
        let b = HealthBackoff(baseSeconds: 60, maxSeconds: 3600)
        let early = HealthExportPlan.make(candidates: cs, policy: .active, now: UTCInstant(epochSeconds: 1119), backoff: b)
        #expect(early.write.isEmpty && early.deferredByBackoff.map(\.subjectID) == ["f"])
        let due = HealthExportPlan.make(candidates: cs, policy: .active, now: UTCInstant(epochSeconds: 1120), backoff: b)
        #expect(due.write.map(\.subjectID) == ["f"])
        let forced = HealthExportPlan.make(candidates: cs, policy: .active, now: UTCInstant(epochSeconds: 1001), backoff: b, force: true)
        #expect(forced.write.map(\.subjectID) == ["f"])
    }

    @Test func unknownIsReconciledAndThenWritten() {
        let plan = HealthExportPlan.make(candidates: [candidate("u", at: 10, .unknown, last: 5, fails: 0), candidate("w", at: 11, .written)],
                                         policy: .active, now: UTCInstant(epochSeconds: 100), backoff: .default)
        #expect(plan.reconcile.map(\.subjectID) == ["u"])
        #expect(plan.write.map(\.subjectID) == ["u"])
    }
}

struct HealthMapperTests {
    @Test func syntheticReadingNeverBecomesExportable() throws {
        // Demuestra la garantía estructural: sin HealthExportable no hay cómo llamar al mapper de glucosa.
        let session = TestSupport.session(synthetic: true)
        let fixture = TestSupport.reading(session, lc: 100, raw: TestSupport.raw(uncapped: 120), origin: .live)
        #expect(fixture.synthetic)
        #expect(HealthExportable(reading: fixture) == nil)
        #expect(HealthExportable(reading: fixture, session: session) == nil)
        // Una lectura marcada real dentro de una sesión sintética tampoco pasa (ajuste Astra).
        var disguised = fixture
        disguised.synthetic = false
        #expect(HealthExportable(reading: disguised, session: session) == nil)
    }

    @Test func qualityFlagAndOutOfRangeAreNotExportable() {
        let session = TestSupport.session()
        let flagged = TestSupport.reading(session, lc: 100, raw: TestSupport.raw(uncapped: 120, qualityFlag: true), origin: .live)
        let warm = TestSupport.reading(session, lc: 5, raw: TestSupport.raw(uncapped: 120), origin: .live)
        #expect(HealthExportable(reading: flagged) == nil)
        #expect(HealthExportable(reading: warm) == nil)
    }

    @Test func glucoseSpecCarriesMetadata() throws {
        let session = TestSupport.session()
        let r = TestSupport.reading(session, lc: 100, raw: TestSupport.raw(uncapped: 120, trend: 3), origin: .live)
        let exportable = try #require(HealthExportable(reading: r, session: session))
        let spec = HealthSampleMapper.spec(for: exportable)
        #expect(spec.kind == .glucose && spec.unit == .milligramsPerDeciliter && spec.value == 120)
        #expect(spec.syncIdentifier == r.recordID && spec.syncVersion == r.revision)
        #expect(spec.wasUserEntered == false)
        #expect(spec.sessionID == session.sessionID && spec.lifeCount == 100 && spec.origin == "live" && spec.trend == 3)
        #expect(spec.date == r.measuredAt)
    }

    private func meal(kind: DiaryEventKind = .meal, carbs: Double? = 40, text: String? = "arepa", synthetic: Bool = false,
                      deleted: Bool = false) -> DiaryEvent {
        DiaryEvent(eventID: TestSupport.newID(), kind: kind, at: UTCInstant(epochSeconds: 1_793_110_000), tz: TestSupport.tz,
                   carbsG: carbs, text: text, createdAt: UTCInstant(epochSeconds: 1), updatedAt: UTCInstant(epochSeconds: 1),
                   revision: 2, editID: TestSupport.newID(), editedByAppID: TestSupport.appID, deleted: deleted, synthetic: synthetic)
    }

    @Test func onlyRealMealsWithCarbsAreExportable() throws {
        #expect(HealthCarbExportable(event: meal(kind: .note)) == nil)
        #expect(HealthCarbExportable(event: meal(kind: .exercise)) == nil)
        #expect(HealthCarbExportable(event: meal(carbs: nil)) == nil)
        #expect(HealthCarbExportable(event: meal(carbs: 0)) == nil)
        #expect(HealthCarbExportable(event: meal(synthetic: true)) == nil)
        #expect(HealthCarbExportable(event: meal(deleted: true)) == nil)
        let ok = try #require(HealthCarbExportable(event: meal()))
        let spec = HealthSampleMapper.spec(for: ok)
        #expect(spec.kind == .carbs && spec.unit == .grams && spec.value == 40 && spec.note == "arepa")
        #expect(spec.syncIdentifier == ok.eventID && spec.syncVersion == 2)
        #expect(HealthCarbExportable(event: meal(text: "  "))?.note == nil)
    }
}
