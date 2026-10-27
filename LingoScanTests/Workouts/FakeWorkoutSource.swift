import Foundation
import LingoCore
import os
@testable import LingoScan

/// Origen sintético: devuelve la lista vigente y registra cada llamada. `WorkoutSource` solo tiene operaciones
/// de lectura (no existe ningún método de escritura que pudiera llamarse); `calls` lo deja comprobable.
final class FakeWorkoutSource: WorkoutSource {
    struct State {
        var workouts: [WorkoutSummary]
        var anchorToReturn: Data? = Data([1])
        var reads = 0
        var anchorsSeen: [Data?] = []
        var authorizationRequests = 0
        var observers = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(workouts: [WorkoutSummary], anchor: Data? = Data([1])) {
        state = OSAllocatedUnfairLock(initialState: State(workouts: workouts, anchorToReturn: anchor))
    }

    var reads: Int { state.withLock { $0.reads } }
    var anchorsSeen: [Data?] { state.withLock { $0.anchorsSeen } }
    /// Toda llamada al origen distinta de la lectura de entrenamientos (permiso, observador).
    var nonReadCalls: Int { state.withLock { $0.authorizationRequests + $0.observers } }

    func setWorkouts(_ workouts: [WorkoutSummary]) { state.withLock { $0.workouts = workouts } }

    func requestReadAuthorization() async throws { state.withLock { $0.authorizationRequests += 1 } }

    func workouts(since anchor: Data?, notBefore: Date) async throws -> WorkoutBatch {
        state.withLock {
            $0.reads += 1
            $0.anchorsSeen.append(anchor)
            return WorkoutBatch(workouts: $0.workouts, anchor: $0.anchorToReturn)
        }
    }

    func observeNewWorkouts() -> AsyncStream<WorkoutChangeNotice> {
        state.withLock { $0.observers += 1 }
        return AsyncStream { $0.finish() }
    }
}
