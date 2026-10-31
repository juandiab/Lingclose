/// Datos de la gráfica AGP del reporte (T-34). Los valores van en mg/dL; las marcas del eje llevan ya su rótulo en la
/// unidad del reporte.
struct MedicalAGP: Sendable, Hashable {
    struct Tick: Sendable, Hashable {
        var mgdl: Double
        var label: String
    }

    var points: [MedicalAGPPoint]
    var targetLow: Double
    var targetHigh: Double
    var yMin: Double
    var yMax: Double
    var ticks: [Tick]
    /// Texto de la leyenda del rango objetivo, con su rango en la unidad del reporte.
    var targetLabel: String

    var hasData: Bool { !points.isEmpty }
}
