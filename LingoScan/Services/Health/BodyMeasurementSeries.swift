import Foundation

/// Todas las mediciones de composición corporal de Apple Salud dentro de un período, por medida y ordenadas por fecha
/// (T-34). A diferencia de `BodyComposition` (último valor y primera/última del período), conserva cada muestra para
/// la tabla del reporte en PDF para el médico. Solo contexto de lectura; nunca se guarda.
struct BodyMeasurementSeries: Sendable, Hashable {
    var samples: [BodyMetric: [BodyMeasurement]] = [:]

    static let empty = BodyMeasurementSeries()

    var isEmpty: Bool { samples.values.allSatisfy(\.isEmpty) }

    /// Muestras finitas de una medida, de la más antigua a la más reciente.
    func measurements(_ metric: BodyMetric) -> [BodyMeasurement] {
        (samples[metric] ?? []).filter { $0.value.isFinite }.sorted { $0.date < $1.date }
    }
}
