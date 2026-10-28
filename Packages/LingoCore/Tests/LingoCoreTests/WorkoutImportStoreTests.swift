import Foundation
import Testing
@testable import LingoCore

/// Entrenamientos de Salud (T-21 §5). Todo sintético.
struct WorkoutImportStoreTests {
    static let start = UTCInstant(epochSeconds: 1_793_110_000)

    @Test func builderMakesReadableExerciseEvent() {
        let w = WorkoutSummary(uuid: "w-1", activityName: "Correr", start: Self.start, end: Self.start.adding(seconds: 1_800),
                               durationMin: 30, activeEnergyKcal: 320.4, distanceMeters: 5_230, averageHeartRate: 141.6)
        let e = WorkoutEventBuilder.event(from: w, eventID: "e", editID: "x1", tz: TestSupport.tz, appID: TestSupport.appID,
                                          now: Self.start.adding(seconds: 2_000))
        #expect(e.kind == .exercise && e.at == Self.start && e.durationMin == 30 && !e.synthetic && e.parentEditID == nil)
        #expect(e.text == "Correr · 5,2 km · 320 kcal · FC media 142")
        #expect(WorkoutEventBuilder.update(existing: e, with: w, editID: "x2", appID: TestSupport.appID, now: Self.start) == nil)
        var longer = w
        longer.durationMin = 45
        let edited = try? #require(WorkoutEventBuilder.update(existing: e, with: longer, editID: "x2", appID: TestSupport.appID,
                                                             now: Self.start.adding(seconds: 3_000)))
        #expect(edited?.durationMin == 45 && edited?.parentEditID == "x1" && edited?.revision == 2)
    }

    @Test func sameWorkoutUUIDNeverCreatesTwoEvents() async throws {
        let store = try TestSupport.makeStore()
        let w = WorkoutSummary(uuid: "w-1", activityName: "Caminar", start: Self.start, end: Self.start.adding(seconds: 600),
                               durationMin: 10)
        func make(_ id: String) -> DiaryEvent {
            WorkoutEventBuilder.event(from: w, eventID: id, editID: TestSupport.newID(), tz: TestSupport.tz,
                                      appID: TestSupport.appID, now: Self.start)
        }
        let first = TestSupport.newID()
        #expect(try await store.saveWorkoutEvent(make(first), workoutUUID: "w-1") == first)
        #expect(try await store.saveWorkoutEvent(make(TestSupport.newID()), workoutUUID: "w-1") == first)
        #expect(try await store.eventID(forWorkoutUUID: "w-1") == first)
        #expect(try await store.events(in: Self.start...Self.start).count == 1)
        #expect(try await store.linkedWorkoutCount() == 1)
        #expect(try await store.isWorkoutEvent(eventID: first))
        #expect(try await !store.isWorkoutEvent(eventID: "manual-exercise"))
    }
}
