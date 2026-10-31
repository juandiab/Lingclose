import LingoCore

/// Un punto de un día en la gráfica de días superpuestos. `series` cambia en cada hueco para no unirlo.
struct OverlayPoint: Identifiable, Hashable, Sendable {
    let id: String
    /// Día local ("2026-10-28").
    let day: String
    /// Minuto local desde la medianoche (centro de la ranura).
    let minute: Int
    let value: Int
    let series: String
    /// Último día del período (hoy): se resalta.
    let isLatest: Bool

    /// Puntos de todos los días, promediando las ranuras de 5 min en ranuras de `slotMinutes`.
    static func points(from days: [DailyOverlayReport.Day], slotMinutes: Int) -> [OverlayPoint] {
        let factor = max(1, slotMinutes / DailyOverlayReport.slotMinutes)
        let latest = days.last?.summary.day.date
        var result: [OverlayPoint] = []
        for day in days {
            let date = day.summary.day.date
            var run = 0
            var previousHadValue = false
            var slot = 0
            while slot < day.values.count {
                let chunk = day.values[slot..<min(slot + factor, day.values.count)].compactMap { $0 }
                if chunk.isEmpty {
                    previousHadValue = false
                } else {
                    if !previousHadValue { run += 1 }
                    previousHadValue = true
                    let value = Int((Double(chunk.reduce(0, +)) / Double(chunk.count)).rounded())
                    let minute = slot * DailyOverlayReport.slotMinutes + slotMinutes / 2
                    result.append(OverlayPoint(
                        id: "\(date)-\(slot)", day: date, minute: minute, value: value,
                        series: "\(date)#\(run)", isLatest: date == latest))
                }
                slot += factor
            }
        }
        return result
    }
}
