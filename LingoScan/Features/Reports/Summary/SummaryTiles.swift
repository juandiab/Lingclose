import LingoCore
import SwiftUI

/// Media, SD, CV, cobertura y huecos del período.
struct SummaryTiles: View {
    let report: PeriodSummaryReport

    var body: some View {
        let stats = report.stats
        ReportStatGrid {
            ReportStatTile(
                title: String(localized: "reports.stat.mean", defaultValue: "Media"),
                value: ReportFormat.mgdl(stats.mean), unit: "mg/dL",
                spoken: stats.mean.map { String(localized: "reports.stat.mean.a11y", defaultValue: "Media, \(Int($0.rounded())) miligramos por decilitro") })
            ReportStatTile(
                title: String(localized: "reports.stat.sd", defaultValue: "SD"),
                value: ReportFormat.mgdl(stats.standardDeviation), unit: "mg/dL",
                spoken: stats.standardDeviation.map { String(localized: "reports.stat.sd.a11y", defaultValue: "Desviación estándar, \(Int($0.rounded())) miligramos por decilitro") })
            ReportStatTile(
                title: String(localized: "reports.stat.cv", defaultValue: "CV"),
                value: ReportFormat.percent(stats.coefficientOfVariation),
                note: String(localized: "reports.stat.cv.note", defaultValue: "variabilidad"),
                spoken: stats.coefficientOfVariation.map { String(localized: "reports.stat.cv.a11y", defaultValue: "Coeficiente de variación, \(ReportFormat.percent($0) ?? "")") })
            ReportStatTile(
                title: String(localized: "reports.stat.coverage", defaultValue: "Cobertura"),
                value: ReportFormat.percent(stats.coverage),
                note: String(localized: "reports.stat.readings", defaultValue: "\(stats.readings) lecturas"))
            ReportStatTile(
                title: String(localized: "reports.stat.gaps", defaultValue: "Huecos"),
                value: "\(report.gaps)",
                note: report.gaps > 0 ? ReportFormat.duration(minutes: report.gapMinutes) : nil,
                spoken: String(localized: "reports.stat.gaps.a11y", defaultValue: "Huecos de más de 10 minutos: \(report.gaps), \(ReportFormat.duration(minutes: report.gapMinutes)) en total"))
        }
    }
}
