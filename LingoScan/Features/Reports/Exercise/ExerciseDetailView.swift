import LingoCore
import SwiftUI

/// Detalle de ejercicio: promedios globales y por duración, y todas las sesiones.
struct ExerciseDetailView: View {
    let content: ReportContent

    var body: some View {
        let report = content.bundle.exercise
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportCard(
                    title: String(localized: "reports.exercise.title", defaultValue: "Efecto del ejercicio"),
                    systemImage: "figure.run",
                    caption: String(
                        localized: "reports.exercise.explainer",
                        defaultValue: "Cambio respecto al nivel de antes de empezar: al terminar, 1 h y 2 h después.")
                ) {
                    ExerciseGroupRow(
                        title: String(localized: "reports.exercise.overall", defaultValue: "Todas las sesiones"),
                        stats: report.overall)
                }
                ReportCard(
                    title: String(localized: "reports.exercise.byDuration", defaultValue: "Por duración"),
                    systemImage: "timer"
                ) {
                    ForEach(report.byDuration.filter { $0.stats.sessions > 0 }, id: \.key) { group in
                        ExerciseGroupRow(title: ReportNames.duration(group.key), stats: group.stats)
                    }
                }
                ForEach(Array(report.sessions.reversed()), id: \.at) { session in
                    ExerciseSessionRow(session: session)
                        .padding(Tokens.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .reportSurface()
                }
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }
}
