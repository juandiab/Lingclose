import LingoCore
import SwiftUI

/// Card de comidas: promedios del período y las últimas comidas con su mini-curva, o qué falta.
struct MealsCardContent: View {
    let content: ReportContent
    /// Comidas recientes que se listan en la card.
    var recentCount = 3

    var body: some View {
        let report = content.bundle.meals
        if report.hasEnoughData {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                MealGroupRow(
                    title: String(localized: "reports.meals.overall", defaultValue: "Todas las comidas"),
                    stats: report.overall)
                Divider()
                ForEach(Array(report.meals.suffix(recentCount).reversed()), id: \.at) { meal in
                    MealResponseRow(meal: meal, curve: content.mealCurves[meal.at] ?? [], configuration: content.configuration)
                }
            }
        } else {
            ReportEmptyState(message: emptyMessage(report))
        }
    }

    private func emptyMessage(_ report: MealResponseReport) -> String {
        if report.meals.isEmpty {
            return String(
                localized: "reports.meals.empty",
                defaultValue: "Anota comidas en el Diario para ver cómo responde tu glucosa. Cada una necesita al menos 1 h de lecturas después.")
        }
        return String(
            localized: "reports.meals.emptyNoResponse",
            defaultValue: "Hay \(report.meals.count) comidas anotadas, pero ninguna tiene al menos 1 h de lecturas seguidas después.")
    }
}
