import Testing
@testable import LingoCore

struct AnalyticsExerciseEffectTests {
    private typealias S = AnalyticsSeries

    /// 120 antes; durante 30 min baja hasta 90; luego sube despacio a 95 a los 60 min del fin.
    private var workout: [BasicStats.Sample] {
        S.series(-20...130) { m in
            switch m {
            case ..<0: 120
            case 0...30: 120 - Double(m)
            default: 90 + Double(m - 30) / 12
            }
        }
    }

    @Test func dropDuringAndAfterExercise() throws {
        let effect = try #require(ExerciseEffect(start: S.t0, samples: workout))
        #expect(effect.end == S.instant(30))
        #expect(effect.before == 120)
        #expect(effect.minAfter == 90)
        #expect(effect.minAt == S.instant(30))
        #expect(effect.deltaAt60 == -25)
    }

    @Test func explicitEndMovesTheSixtyMinuteMark() throws {
        let effect = try #require(ExerciseEffect(start: S.t0, end: S.instant(10), samples: workout))
        // Fin a los 10 min: lectura a los 70 min = 90 + 40/12 ≈ 93.
        #expect(effect.deltaAt60 == -27)
    }

    @Test func withoutDataThereIsNoEffect() {
        #expect(ExerciseEffect(start: S.t0, samples: []) == nil)
        // Sin lecturas previas.
        #expect(ExerciseEffect(start: S.t0, samples: workout.filter { $0.measuredAt >= S.t0 }) == nil)
    }

    @Test func noReadingNearSixtyMinutesLeavesDeltaEmpty() throws {
        let cut = workout.filter { $0.measuredAt <= S.instant(60) }
        let effect = try #require(ExerciseEffect(start: S.t0, samples: cut))
        #expect(effect.deltaAt60 == nil)
        #expect(effect.minAfter == 90)
    }
}
