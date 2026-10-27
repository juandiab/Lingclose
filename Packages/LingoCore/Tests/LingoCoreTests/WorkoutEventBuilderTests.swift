import Testing
@testable import LingoCore

/// `WorkoutEventBuilder.update` (T-21 §5): linaje, "sin cambios" y evento borrado. Todo sintético.
struct WorkoutEventBuilderTests {
    static let start = UTCInstant(epochSeconds: 1_793_110_000)

    private func workout(duration: Int = 30) -> WorkoutSummary {
        WorkoutSummary(uuid: "w-1", activityName: "Correr", start: Self.start,
                       end: Self.start.adding(seconds: Int64(duration) * 60), durationMin: duration, activeEnergyKcal: 300)
    }

    private func created() -> DiaryEvent {
        WorkoutEventBuilder.event(from: workout(), eventID: "e-1", editID: "x1", tz: TestSupport.tz, appID: TestSupport.appID,
                                  now: Self.start.adding(seconds: 2_000))
    }

    @Test func changedDurationCreatesEditWithLineage() throws {
        let original = created()
        let now = Self.start.adding(seconds: 5_000)
        let edited = try #require(WorkoutEventBuilder.update(existing: original, with: workout(duration: 45), editID: "x2",
                                                             appID: TestSupport.appID, now: now))
        #expect(edited.eventID == original.eventID && edited.kind == .exercise)
        #expect(edited.durationMin == 45)
        #expect(edited.editID == "x2" && edited.parentEditID == "x1")
        #expect(edited.revision == original.revision + 1)
        #expect(edited.updatedAt == now && edited.createdAt == original.createdAt)
        #expect(edited.deleted == false && edited.synthetic == false)
    }

    @Test func unchangedWorkoutReturnsNil() {
        #expect(WorkoutEventBuilder.update(existing: created(), with: workout(), editID: "x2", appID: TestSupport.appID,
                                           now: Self.start) == nil)
    }

    @Test func deletedEventIsNeverResurrected() {
        var deleted = created()
        deleted.deleted = true
        #expect(WorkoutEventBuilder.update(existing: deleted, with: workout(duration: 90), editID: "x2",
                                           appID: TestSupport.appID, now: Self.start) == nil)
    }
}
