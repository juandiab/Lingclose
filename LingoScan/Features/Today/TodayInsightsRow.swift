import LingoCore
import SwiftUI

/// Fila compacta "Insights" bajo las estadísticas (misma estética que En rango/Media/SD): cambios rápidos de
/// la ventana visible y la mejor y la peor respuesta a comida. Tocarla abre la hoja con el detalle.
struct TodayInsightsRow: View {
    let insights: TodayInsights
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HStack(spacing: Tokens.Spacing.xxs) {
                    Text(String(localized: "today.insights.title", defaultValue: "Insights · informativo"))
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                let rates = PeriodStatMetric(
                    title: String(localized: "today.insights.rates", defaultValue: "Cambios rápidos"),
                    value: "↑\(insights.risingCount) ↓\(insights.fallingCount)",
                    spoken: String(localized: "today.insights.rates.a11y", defaultValue: "Subidas rápidas: \(insights.risingCount); bajadas rápidas: \(insights.fallingCount)"))
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Tokens.Spacing.sm) { rates; meals }
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xs) { rates; meals }
                }
                .padding(.trailing, PeriodStatsCard.addButtonClearance)
            }
            .padding(.vertical, Tokens.Spacing.xxs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "today.insights.hint", defaultValue: "Muestra los cambios rápidos y la respuesta a cada comida"))
    }

    @ViewBuilder
    private var meals: some View {
        if let best = insights.best {
            metric(best, title: insights.worst == nil
                ? String(localized: "today.insights.meal", defaultValue: "Comida")
                : String(localized: "today.insights.best", defaultValue: "Mejor comida"))
        }
        if let worst = insights.worst {
            metric(worst, title: String(localized: "today.insights.worst", defaultValue: "Peor comida"))
        }
    }

    /// "+42 mg/dL · 50 min" con el nombre de la comida si lo tiene.
    private func metric(_ meal: TodayMealInsight, title: String) -> PeriodStatMetric {
        let rise = InsightFormat.rise(meal.response)
        let peak = InsightFormat.minutes(meal.response.timeToPeak)
        let label = meal.mark.text.flatMap { $0.isEmpty ? nil : $0 }.map { "\(title) · \($0)" } ?? title
        return PeriodStatMetric(
            title: label,
            value: "+\(rise)",
            unit: String(localized: "today.insights.meal.unit", defaultValue: "mg/dL · \(peak) min"),
            spoken: String(localized: "today.insights.meal.a11y", defaultValue: "\(label): subió \(rise) miligramos por decilitro, pico a los \(peak) minutos"))
    }
}
