import LingoCore
import SwiftUI

/// Parte del popover de una marca con el insight de T-23: respuesta a la comida (frase y puntuación) o efecto
/// del ejercicio a los 60 min; "sin datos suficientes (todavía)" si no se puede calcular.
struct DiaryMarkInsight: View {
    let mark: DiaryMark
    let mealResponse: MealResponse?
    let exerciseEffect: ExerciseEffect?
    let now: Date

    var body: some View {
        switch mark.kind {
        case .meal:
            if let mealResponse {
                MealResponseSummary(response: mealResponse)
            } else {
                Text(InsightFormat.notEnoughData(since: mark.date, now: now))
                    .foregroundStyle(.secondary)
            }
        case .exercise:
            if let summary = exerciseEffect.flatMap(InsightFormat.exerciseSummary) {
                Text(summary)
                    .monospacedDigit()
            } else {
                Text(InsightFormat.notEnoughData(since: mark.endDate ?? mark.date, now: now))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
