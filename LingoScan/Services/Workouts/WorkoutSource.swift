import Foundation
import LingoCore

/// Origen de entrenamientos (T-21 §5). **Solo lectura**: ninguna implementación escribe en Salud.
protocol WorkoutSource: Sendable {
    /// Pide permiso de lectura de entrenamientos (y de sus estadísticas). Nunca pide escritura.
    func requestReadAuthorization() async throws
    /// Entrenamientos añadidos desde `anchor` (opaco; `nil` = primera vez) que empiezan en `notBefore` o después.
    func workouts(since anchor: Data?, notBefore: Date) async throws -> WorkoutBatch
    /// Un aviso por cada cambio en los entrenamientos de Salud. Quien lo recibe importa y llama a `acknowledge()`.
    func observeNewWorkouts() -> AsyncStream<WorkoutChangeNotice>
}
