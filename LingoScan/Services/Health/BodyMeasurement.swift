import Foundation

/// Un valor de una medida corporal con su instante, ya en la unidad del contexto (kg, %, cm) (T-33).
struct BodyMeasurement: Sendable, Hashable {
    var date: Date
    var value: Double
}
