/// Percentiles de una media hora del día local (mg/dL). `minute` es el inicio de la media hora.
struct MedicalAGPPoint: Sendable, Hashable {
    var minute: Int
    var p5: Double
    var p25: Double
    var p50: Double
    var p75: Double
    var p95: Double
}
