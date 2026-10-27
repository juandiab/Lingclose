import Foundation
import LingoCore

extension AppEnvironment {
    /// Importación de entrenamientos de Salud (T-21 §5, solo lectura). Se crea en `init` para que el observador de
    /// Salud exista también cuando iOS relanza la app en segundo plano por un entrenamiento nuevo.
    static func makeWorkoutImport(store: SQLiteStore) -> WorkoutImportTrigger {
        let source = HealthKitWorkoutSource()
        return WorkoutImportTrigger(importer: WorkoutImporter(source: source, store: store), source: source)
    }
}
