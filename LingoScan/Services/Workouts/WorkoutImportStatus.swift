import Foundation

/// Lo que muestra Ajustes: última importación, su resultado y cuántos entrenamientos hay enlazados.
struct WorkoutImportStatus: Sendable, Equatable {
    var lastImportAt: Date?
    var lastReport: WorkoutImportReport?
    var totalImported: Int
}
