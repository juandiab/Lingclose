import LingoCore

/// Una media hora del perfil por hora con percentiles; `run` separa tramos sin datos (las áreas no los cruzan).
struct HourlyProfilePoint: Identifiable, Hashable, Sendable {
    let id: Int
    /// Centro de la media hora, en minutos desde la medianoche local.
    let minute: Int
    let run: Int
    let p5: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p95: Double

    /// Solo las medias horas con percentiles (≥ `ReportThresholds.minimumDaysPerHourlyBin` días).
    static func points(from report: HourlyProfileReport) -> [HourlyProfilePoint] {
        var result: [HourlyProfilePoint] = []
        var run = 0
        var previousReported = false
        for (index, bin) in report.bins.enumerated() {
            guard let p5 = bin.p5, let p25 = bin.p25, let p50 = bin.p50, let p75 = bin.p75, let p95 = bin.p95 else {
                previousReported = false
                continue
            }
            if !previousReported { run += 1 }
            previousReported = true
            result.append(HourlyProfilePoint(
                id: index, minute: bin.startMinute + HourlyProfileReport.binMinutes / 2, run: run,
                p5: p5, p25: p25, p50: p50, p75: p75, p95: p95))
        }
        return result
    }
}
