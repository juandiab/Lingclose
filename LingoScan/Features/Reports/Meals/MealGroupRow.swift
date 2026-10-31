import LingoCore
import SwiftUI

/// Agregado de comidas (global, por franja o por carbohidratos): subida media, pico medio y cuántas volvieron.
struct MealGroupRow: View {
    let title: String
    let stats: MealResponseReport.Stats

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: Tokens.Spacing.xs)
                Text(String(localized: "reports.meals.count", defaultValue: "\(stats.analyzed) de \(stats.meals) medidas"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if stats.isReliable {
                ReportStatGrid {
                    ReportStatTile(
                        title: String(localized: "reports.meals.meanRise", defaultValue: "Subida media"),
                        value: stats.meanRise.map { ReportFormat.signed($0) }, unit: "mg/dL")
                    ReportStatTile(
                        title: String(localized: "reports.meals.meanPeak", defaultValue: "Pico medio"),
                        value: ReportFormat.mgdl(stats.meanPeak), unit: "mg/dL")
                    ReportStatTile(
                        title: String(localized: "reports.meals.timeToPeak", defaultValue: "Hasta el pico"),
                        value: stats.meanTimeToPeakMinutes.map { ReportFormat.duration(minutes: Int($0.rounded())) })
                    ReportStatTile(
                        title: String(localized: "reports.meals.returned", defaultValue: "Volvieron en 3 h"),
                        value: ReportFormat.percent(stats.returnedFraction))
                }
            } else {
                Text(String(
                    localized: "reports.meals.groupTooFew",
                    defaultValue: "Los promedios necesitan al menos \(ReportThresholds.minimumEventsPerGroup) comidas medidas."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
