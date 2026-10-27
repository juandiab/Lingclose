import Foundation
import LingoCore

/// Resultado de una consulta incremental: entrenamientos nuevos y el anchor para la siguiente.
struct WorkoutBatch: Sendable {
    var workouts: [WorkoutSummary]
    /// `HKQueryAnchor` archivado; `nil` si el origen no lo da.
    var anchor: Data?
}
