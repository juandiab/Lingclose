import LingoCore

/// Tiempo en rangos con los cortes del consenso, calculado sobre la serie remuestreada del período (5 min hasta 31
/// días, 15 min después). Cada ranura con lectura cuenta una vez; los huecos no cuentan (T-34).
struct MedicalTimeInRange: Sendable, Hashable {
    /// Ranuras con lectura en cada tramo, en el orden de `MedicalRangeBand.allCases`.
    let counts: [Int]

    init(series: ResampledSeries) {
        var counts = [Int](repeating: 0, count: MedicalRangeBand.allCases.count)
        for value in series.values {
            guard let value else { continue }
            counts[MedicalRangeBand(mgdl: value).rawValue] += 1
        }
        self.counts = counts
    }

    var total: Int { counts.reduce(0, +) }
    var hasData: Bool { total > 0 }

    /// Fracción 0…1 del tiempo con lectura en el tramo; 0 sin datos.
    func fraction(_ band: MedicalRangeBand) -> Double {
        total > 0 ? Double(counts[band.rawValue]) / Double(total) : 0
    }
}
