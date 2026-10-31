import LingoCore
import SwiftUI

/// Agregado de ejercicio (global o por duración): cambio medio al terminar, a 1 h y a 2 h, y bajada al mínimo.
struct ExerciseGroupRow: View {
    let title: String
    let stats: ExerciseEffectReport.Stats

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: Tokens.Spacing.xs)
                Text(String(localized: "reports.exercise.count", defaultValue: "\(stats.analyzed) de \(stats.sessions) medidas"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if stats.isReliable {
                ReportStatGrid {
                    tile(String(localized: "reports.exercise.atEnd", defaultValue: "Al terminar"), stats.meanDeltaAtEnd)
                    tile(String(localized: "reports.exercise.at60", defaultValue: "1 h después"), stats.meanDeltaAt60)
                    tile(String(localized: "reports.exercise.at120", defaultValue: "2 h después"), stats.meanDeltaAt120)
                    tile(String(localized: "reports.exercise.drop", defaultValue: "Bajada al mínimo"), stats.meanDropToMinimum)
                }
            } else {
                Text(String(
                    localized: "reports.exercise.groupTooFew",
                    defaultValue: "Los promedios necesitan al menos \(ReportThresholds.minimumEventsPerGroup) sesiones medidas."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tile(_ title: String, _ value: Double?) -> ReportStatTile {
        ReportStatTile(title: title, value: value.map { ReportFormat.signed($0) }, unit: "mg/dL")
    }
}
