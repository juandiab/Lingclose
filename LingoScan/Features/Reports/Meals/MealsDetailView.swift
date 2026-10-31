import LingoCore
import SwiftUI

/// Detalle de comidas: promedios por franja y por carbohidratos, y todas las comidas del período.
struct MealsDetailView: View {
    let content: ReportContent

    var body: some View {
        let report = content.bundle.meals
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ReportCard(
                    title: String(localized: "reports.meals.title", defaultValue: "Respuesta a comidas"),
                    systemImage: "fork.knife",
                    caption: String(
                        localized: "reports.meals.explainer",
                        defaultValue: "Subida: del nivel antes de comer al pico en 3 h. Volvió: tiempo hasta quedar a 10 mg/dL del nivel previo.")
                ) {
                    MealGroupRow(
                        title: String(localized: "reports.meals.overall", defaultValue: "Todas las comidas"),
                        stats: report.overall)
                }
                ReportCard(
                    title: String(localized: "reports.meals.bySlot", defaultValue: "Por franja del día"),
                    systemImage: "sun.horizon"
                ) {
                    ForEach(report.bySlot.filter { $0.stats.meals > 0 }, id: \.key) { group in
                        MealGroupRow(title: "\(ReportNames.slot(group.key)) (\(ReportNames.slotHours(group.key)))", stats: group.stats)
                    }
                }
                ReportCard(
                    title: String(localized: "reports.meals.byCarbs", defaultValue: "Por carbohidratos"),
                    systemImage: "chart.bar"
                ) {
                    ForEach(report.byCarbs.filter { $0.stats.meals > 0 }, id: \.key) { group in
                        MealGroupRow(title: ReportNames.carbs(group.key), stats: group.stats)
                    }
                }
                // Una fila por comida directamente en la pila perezosa: con 90 días pueden ser cientos de mini-curvas.
                Text(String(localized: "reports.meals.all", defaultValue: "Todas, de la más reciente"))
                    .font(.headline)
                    .padding(.top, Tokens.Spacing.xs)
                ForEach(Array(report.meals.reversed()), id: \.at) { meal in
                    MealResponseRow(meal: meal, curve: content.mealCurves[meal.at] ?? [], configuration: content.configuration)
                        .padding(Tokens.Spacing.sm)
                        .reportSurface()
                }
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }
}
