import LingoCore

/// Fracción de lecturas de una banda (bajo / en rango / alto / muy alto) en unas estadísticas.
struct ReportBandShare: Identifiable, Hashable {
    let band: GlucoseBand
    let fraction: Double

    var id: GlucoseBand { band }

    /// Las cuatro bandas en orden; vacío si no hay lecturas. "Alto" excluye "muy alto".
    static func shares(_ stats: GlucoseStats) -> [ReportBandShare] {
        guard stats.hasReadings else { return [] }
        let veryHigh = stats.timeVeryHigh ?? 0
        return [
            ReportBandShare(band: .low, fraction: stats.timeLow ?? 0),
            ReportBandShare(band: .inRange, fraction: stats.timeInRange ?? 0),
            ReportBandShare(band: .high, fraction: max(0, (stats.timeHigh ?? 0) - veryHigh)),
            ReportBandShare(band: .veryHigh, fraction: veryHigh),
        ]
    }
}
