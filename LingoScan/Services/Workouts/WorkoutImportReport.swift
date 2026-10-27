/// Resultado de una importación de entrenamientos.
struct WorkoutImportReport: Sendable, Equatable, Codable {
    var imported = 0
    var updated = 0
    var unchanged = 0

    var changed: Int { imported + updated }
}
