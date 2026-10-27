import Testing
@testable import LingoCore

struct HealthLedgerTests {
    private func entry(_ subject: String, _ result: HealthLedgerResult, version: Int = 1, at: Int64,
                       writer: String = TestSupport.appID) -> HealthLedgerEntry {
        HealthLedgerEntry(attemptID: TestSupport.newID(), subjectID: subject, subjectKind: .glucose, writerAppID: writer,
                          syncIdentifier: subject, syncVersion: version, exportedAt: UTCInstant(epochSeconds: at), result: result)
    }

    @Test func failedThenWrittenIsWrittenAndLaterFailureDoesNotEraseIt() async throws {
        let store = try TestSupport.makeStore()
        let subject = "s1"
        #expect(try await store.derivedHealthState(subjectID: subject, writerAppID: TestSupport.appID) == .none)
        let failed = entry(subject, .failed, at: 10)
        #expect(try await store.appendLedger(failed))
        #expect(try await store.appendLedger(failed) == false)  // mismo attempt_id: unión, no duplicado
        #expect(try await store.derivedHealthState(subjectID: subject, writerAppID: TestSupport.appID) == .failed)
        try await store.appendLedger(entry(subject, .written, at: 20))
        #expect(try await store.derivedHealthState(subjectID: subject, writerAppID: TestSupport.appID) == .written)
        try await store.appendLedger(entry(subject, .failed, at: 30))
        #expect(try await store.derivedHealthState(subjectID: subject, writerAppID: TestSupport.appID) == .written)
        #expect(try await store.ledgerEntries(subjectID: subject).map(\.result) == [.failed, .written, .failed])
        // Otra escritora no hereda el estado.
        #expect(try await store.derivedHealthState(subjectID: subject, writerAppID: "com.otalvaro.lingoscan.astra") == .none)
    }

    @Test func unknownAndNewerVersion() async throws {
        let store = try TestSupport.makeStore()
        try await store.appendLedger(entry("s2", .unknown, at: 10))
        #expect(try await store.derivedHealthState(subjectID: "s2", writerAppID: TestSupport.appID) == .unknown)
        try await store.appendLedger(entry("s3", .written, version: 1, at: 10))
        try await store.appendLedger(entry("s3", .failed, version: 2, at: 20))
        #expect(try await store.derivedHealthState(subjectID: "s3", writerAppID: TestSupport.appID) == .failed)
        try await store.appendLedger(entry("s3", .written, version: 2, at: 30))
        #expect(try await store.derivedHealthState(subjectID: "s3", writerAppID: TestSupport.appID) == .written)
    }

    @Test func pendingSubjectsExcludeWrittenSyntheticAndExcluded() async throws {
        let store = try TestSupport.makeStore()
        let real = TestSupport.session()
        let synthetic = TestSupport.session(synthetic: true)
        try await store.upsertSession(real)
        try await store.upsertSession(synthetic)
        let a = TestSupport.reading(real, lc: 100, raw: TestSupport.raw(uncapped: 120), origin: .live)
        let b = TestSupport.reading(real, lc: 101, raw: TestSupport.raw(uncapped: 121), origin: .live)
        let excluded = TestSupport.reading(real, lc: 102, raw: TestSupport.raw(qualityFlag: true), origin: .live)
        let fixture = TestSupport.reading(synthetic, lc: 100, raw: TestSupport.raw(uncapped: 120), origin: .live)
        try await store.insertReadings([a, b, excluded, fixture])
        let meal = DiaryEvent(eventID: TestSupport.newID(), kind: .meal, at: UTCInstant(epochSeconds: 1_793_110_000),
                              tz: TestSupport.tz, carbsG: 30, createdAt: UTCInstant(epochSeconds: 1_793_110_000),
                              updatedAt: UTCInstant(epochSeconds: 1_793_110_000), editID: TestSupport.newID(),
                              editedByAppID: TestSupport.appID, synthetic: false)
        try await store.upsertEvent(meal)
        #expect(Set(try await store.pendingHealthSubjects().map(\.subjectID)) == [a.recordID, b.recordID, meal.eventID])
        try await store.appendLedger(entry(a.recordID, .failed, at: 10))
        try await store.appendLedger(entry(a.recordID, .written, at: 20, writer: "com.otalvaro.lingoscan.astra"))
        let pending = try await store.pendingHealthSubjects()
        #expect(pending.map(\.subjectID) == [b.recordID, meal.eventID])
        #expect(pending.map(\.subjectKind) == [.glucose, .carbs])
    }
}
