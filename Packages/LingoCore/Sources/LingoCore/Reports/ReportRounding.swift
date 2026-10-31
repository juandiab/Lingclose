/// Redondeo fijo de los valores de los reportes: hace el JSON corto y estable entre ejecuciones.
enum ReportRounding {
    /// mg/dL, minutos medios y pendientes: 1 decimal.
    static func r1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    /// Fracciones 0…1: 3 decimales.
    static func r3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

    static func r1(optional value: Double?) -> Double? { value.map { r1($0) } }
    static func r3(optional value: Double?) -> Double? { value.map { r3($0) } }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Mediana (tipo 7, como `GlucoseDistribution.percentile(50)`).
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
