import Foundation
import LingoCore

extension MedicalReportBuilder {
    /// Ventanas de la tabla del AGP: 12 de 2 horas (cuatro medias horas cada una).
    static let agpWindowMinutes = 120

    // MARK: AGP

    static func agpSection(_ bundle: ReportBundle, _ f: MedicalReportFormatter) -> (chart: MedicalAGP, table: MedicalTable?) {
        let bins = bundle.hourlyProfile.bins
        let points = bins.compactMap { bin -> MedicalAGPPoint? in
            guard let p5 = bin.p5, let p25 = bin.p25, let p50 = bin.p50, let p75 = bin.p75, let p95 = bin.p95 else { return nil }
            return MedicalAGPPoint(minute: bin.startMinute, p5: p5, p25: p25, p50: p50, p75: p75, p95: p95)
        }
        let top = points.map(\.p95).max() ?? 0
        let yMax = max(250, (top / 50).rounded(.up) * 50)
        let chart = MedicalAGP(points: points, targetLow: targetLow, targetHigh: targetHigh, yMin: 40, yMax: yMax,
                               ticks: ticks(yMax: yMax, f),
                               targetLabel: "\(S.agpTarget) \(rangeTexts(f)[MedicalRangeBand.target.rawValue]) \(f.unit.symbol)")
        guard !points.isEmpty else { return (chart, nil) }
        return (chart, agpTable(bins, f))
    }

    /// Marcas del eje vertical: cada 50 mg/dL (100 si pasa de 400) o cada 2 mmol/L.
    static func ticks(yMax: Double, _ f: MedicalReportFormatter) -> [MedicalAGP.Tick] {
        switch f.unit {
        case .mgdl:
            let step = yMax > 400 ? 100.0 : 50.0
            return stride(from: step, through: yMax, by: step).map { MedicalAGP.Tick(mgdl: $0, label: f.glucose($0)) }
        case .mmol:
            let top = Int(yMax / MedicalGlucoseUnit.mmolFactor)
            return stride(from: 2, through: max(2, top), by: 2).map {
                MedicalAGP.Tick(mgdl: Double($0) * MedicalGlucoseUnit.mmolFactor, label: f.number(Double($0)))
            }
        }
    }

    private static func agpTable(_ bins: [HourlyProfileReport.Bin], _ f: MedicalReportFormatter) -> MedicalTable {
        let windows = 1_440 / agpWindowMinutes
        var columns = [MedicalTableColumn(title: S.agpHour, weight: 2.4, alignment: .leading)]
        var median: [String] = [S.agpMedian], iqr: [String] = [S.agpIQR], wide: [String] = [S.agpWide], days: [String] = [S.agpDays]
        for window in 0..<windows {
            let start = window * agpWindowMinutes / 60
            columns.append(MedicalTableColumn(
                title: String(format: "%02d–%02d", start, start + agpWindowMinutes / 60), weight: 1, alignment: .center))
            let inWindow = bins.filter { $0.startMinute / agpWindowMinutes == window && $0.isReported }
            func weighted(_ value: (HourlyProfileReport.Bin) -> Double?) -> Double? {
                let pairs = inWindow.compactMap { bin in value(bin).map { ($0, Double(bin.readings)) } }
                let weight = pairs.reduce(0) { $0 + $1.1 }
                guard weight > 0 else { return nil }
                return pairs.reduce(0) { $0 + $1.0 * $1.1 } / weight
            }
            let p5 = weighted(\.p5), p25 = weighted(\.p25), p50 = weighted(\.p50), p75 = weighted(\.p75), p95 = weighted(\.p95)
            median.append(f.glucose(p50))
            iqr.append(range(p25, p75, f))
            wide.append(range(p5, p95, f))
            days.append(inWindow.isEmpty ? MedicalReportFormatter.dash : String(inWindow.map(\.days).max() ?? 0))
        }
        return MedicalTable(id: "agpTable", title: S.agpTableTitle, subtitle: nil, columns: columns,
                            rows: [median, iqr, wide, days])
    }

    private static func range(_ low: Double?, _ high: Double?, _ f: MedicalReportFormatter) -> String {
        guard let low, let high else { return MedicalReportFormatter.dash }
        return "\(f.glucose(low))–\(f.glucose(high))"
    }

    // MARK: Franjas del día

    static func slotsTable(_ bundle: ReportBundle, _ f: MedicalReportFormatter) -> MedicalTable? {
        let slots = bundle.timeOfDay.slots.filter { $0.stats.hasReadings }
        guard !slots.isEmpty else { return nil }
        let configuration = bundle.configuration
        let columns = [
            MedicalTableColumn(title: S.slot, weight: 3, alignment: .leading),
            MedicalTableColumn(title: S.mean, weight: 1.4),
            MedicalTableColumn(title: S.inRangeColumn(f.glucose(Double(configuration.rangeLow)), f.glucose(Double(configuration.rangeHigh))), weight: 2),
            MedicalTableColumn(title: S.sdShort, weight: 1.2),
            MedicalTableColumn(title: S.fastRises, weight: 2),
            MedicalTableColumn(title: S.fastFalls, weight: 2),
            MedicalTableColumn(title: S.daysColumn, weight: 1),
        ]
        let rows = slots.map { slot -> [String] in
            [slotName(slot.slot), f.glucose(slot.stats.mean), f.percent(slot.stats.timeInRange), f.glucose(slot.stats.standardDeviation),
             slot.fastRisesPerDay.map { f.number($0, decimals: 1) } ?? MedicalReportFormatter.dash,
             slot.fastFallsPerDay.map { f.number($0, decimals: 1) } ?? MedicalReportFormatter.dash,
             String(slot.days)]
        }
        return MedicalTable(id: "slots", title: S.slotsTitle, subtitle: S.slotsSubtitle, columns: columns, rows: rows)
    }

    static func slotName(_ slot: TimeOfDaySlot) -> String {
        switch slot {
        case .morning: S.morning
        case .midday: S.midday
        case .evening: S.evening
        case .night: S.night
        }
    }

    // MARK: Comparación semanal

    static func weeklyTable(_ bundle: ReportBundle, _ f: MedicalReportFormatter) -> MedicalTable? {
        let report = bundle.weeklyComparison
        guard let current = report.current, let previous = report.previous, let deltas = report.deltas else { return nil }
        func pp(_ fraction: Double?) -> String {
            fraction.map { f.signed($0 * 100, decimals: 1) + " pp" } ?? MedicalReportFormatter.dash
        }
        func count(_ delta: Int) -> String { f.signed(Double(delta)) }
        let columns = [
            MedicalTableColumn(title: S.measure, weight: 3, alignment: .leading),
            MedicalTableColumn(title: S.previousWeek, weight: 1.6),
            MedicalTableColumn(title: S.currentWeek, weight: 1.6),
            MedicalTableColumn(title: S.change, weight: 1.6),
        ]
        let rows: [[String]] = [
            [S.meanGlucose(f.unit.symbol), f.glucose(previous.stats.mean), f.glucose(current.stats.mean), f.glucoseDelta(deltas.mean)],
            [S.timeInRange, f.percent(previous.stats.timeInRange, decimals: 1), f.percent(current.stats.timeInRange, decimals: 1), pp(deltas.timeInRange)],
            [S.sd(f.unit.symbol), f.glucose(previous.stats.standardDeviation), f.glucose(current.stats.standardDeviation), f.glucoseDelta(deltas.standardDeviation)],
            [S.cv, f.percent(previous.stats.coefficientOfVariation, decimals: 1), f.percent(current.stats.coefficientOfVariation, decimals: 1), pp(deltas.coefficientOfVariation)],
            [S.daysLabel, String(previous.daysWithData), String(current.daysWithData), count(current.daysWithData - previous.daysWithData)],
            [S.meals, String(previous.meals), String(current.meals), count(deltas.meals)],
            [S.exerciseMinutes, String(previous.exerciseMinutes), String(current.exerciseMinutes), count(deltas.exerciseMinutes)],
        ]
        func span(_ week: WeeklyComparisonReport.Week) -> String {
            guard let first = MedicalReportFormatter.isoDay(week.firstDay, timeZone: f.timeZone),
                  let last = MedicalReportFormatter.isoDay(week.lastDay, timeZone: f.timeZone) else { return "\(week.firstDay) – \(week.lastDay)" }
            return "\(f.shortDay(first)) – \(f.shortDay(last))".trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        return MedicalTable(id: "weekly", title: S.weeklyTitle, subtitle: S.weeklySubtitle(span(previous), span(current)),
                            columns: columns, rows: rows)
    }

    // MARK: Perfiles diarios

    static func dailySection(_ bundle: ReportBundle, _ f: MedicalReportFormatter) -> [MedicalDailyProfile] {
        bundle.dailyOverlay.days.map { day in
            let stats = day.summary.stats
            let caption = stats.hasReadings
                ? "\(f.glucose(stats.mean)) · \(f.percent(stats.timeInRange))"
                : S.dailyNoData
            return MedicalDailyProfile(label: f.weekdayDay(day.summary.day.start.date), caption: caption, values: day.values)
        }
    }
}
