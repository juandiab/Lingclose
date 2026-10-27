import Foundation
import LingoCore
import os
@testable import LingoScan

/// Origen sintético: devuelve siempre la misma lista y registra las llamadas (solo hay operaciones de lectura).
final class FakeWorkoutSource: WorkoutSource {
    private let state: OSAllocatedUnfairLock<(workouts: [WorkoutSummary], reads: Int)>

    init(workouts: [WorkoutSummary]) {
        state = OSAllocatedUnfairLock(initialState: (workouts, 0))
    }

    var reads: Int { state.withLock { $0.reads } }

    func requestReadAuthorization() async throws {}

    func workouts(since anchor: Data?, notBefore: Date) async throws -> WorkoutBatch {
        state.withLock {
            $0.reads += 1
            return WorkoutBatch(workouts: $0.workouts, anchor: Data([1]))
        }
    }

    func observeNewWorkouts() -> AsyncStream<WorkoutChangeNotice> {
        AsyncStream { $0.finish() }
    }
}
