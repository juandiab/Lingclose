import LingoCore
import SwiftUI

/// Resumen de las noches fiables: mediana típica, mínimo medio, tiempo en rango y noches con bajada.
struct NightSummaryTiles: View {
    let summary: NightReport.Summary

    var body: some View {
        ReportStatGrid {
            ReportStatTile(
                title: String(localized: "reports.nights.median", defaultValue: "Mediana típica"),
                value: ReportFormat.mgdl(summary.medianOfMedians), unit: "mg/dL")
            ReportStatTile(
                title: String(localized: "reports.nights.meanMinimum", defaultValue: "Mínimo medio"),
                value: ReportFormat.mgdl(summary.meanMinimum), unit: "mg/dL")
            ReportStatTile(
                title: String(localized: "reports.stat.tir", defaultValue: "En rango"),
                value: ReportFormat.percent(summary.meanTimeInRange))
            ReportStatTile(
                title: String(localized: "reports.nights.withLow", defaultValue: "Noches con bajada"),
                value: summary.nightsWithLowEpisode.map { "\($0)" },
                note: String(localized: "reports.nights.ofReliable", defaultValue: "de \(summary.reliableNights) noches"))
        }
    }
}
