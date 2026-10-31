import LingoCore
import SwiftUI

/// Card de ejercicio: promedios y las últimas sesiones, o qué falta.
struct ExerciseCardContent: View {
    let report: ExerciseEffectReport
    var recentCount = 3

    var body: some View {
        if report.hasEnoughData {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ExerciseGroupRow(
                    title: String(localized: "reports.exercise.overall", defaultValue: "Todas las sesiones"),
                    stats: report.overall)
                Divider()
                ForEach(Array(report.sessions.suffix(recentCount).reversed()), id: \.at) { session in
                    ExerciseSessionRow(session: session)
                }
            }
        } else if report.sessions.isEmpty {
            ReportEmptyState(message: String(
                localized: "reports.exercise.empty",
                defaultValue: "Anota ejercicio en el Diario (o impórtalo de Salud) para ver cómo cambia tu glucosa durante y después."),
                systemImage: "figure.run")
        } else {
            ReportEmptyState(message: String(
                localized: "reports.exercise.emptyNoEffect",
                defaultValue: "Hay \(report.sessions.count) sesiones, pero ninguna tiene lecturas suficientes durante y después."),
                systemImage: "figure.run")
        }
    }
}
