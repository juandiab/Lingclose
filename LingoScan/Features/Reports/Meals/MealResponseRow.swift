import LingoCore
import SwiftUI

/// Una comida: cuándo, carbohidratos y franja, su respuesta (subida, pico, retorno) y la mini-curva de 3 h.
struct MealResponseRow: View {
    let meal: MealResponseReport.Meal
    let curve: [MealSparkPoint]
    let configuration: ReportConfiguration

    @ScaledMetric(relativeTo: .subheadline) private var sparklineWidth = 96.0
    @ScaledMetric(relativeTo: .subheadline) private var sparklineHeight = 44.0

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Text(ReportFormat.dateTime(meal.at))
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                if let response = meal.response {
                    MealResponseFacts(response: response)
                } else {
                    Text(String(
                        localized: "reports.meal.noResponse",
                        defaultValue: "Sin lecturas suficientes después para medir la respuesta."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if curve.count > 1 {
                MealSparkline(points: curve, baseline: meal.response?.baseline, configuration: configuration)
                    .frame(width: sparklineWidth, height: sparklineHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var subtitle: String {
        var parts = [ReportNames.slot(meal.slot)]
        if let carbs = meal.carbsG {
            parts.append(String(localized: "reports.meal.carbs", defaultValue: "\(Int(carbs.rounded())) g de carbohidratos"))
        }
        if meal.overlapsPreviousMeal {
            parts.append(String(localized: "reports.meal.overlaps", defaultValue: "cerca de otra comida"))
        }
        return parts.joined(separator: " · ")
    }

    private var spoken: String {
        let head = "\(ReportFormat.dateTime(meal.at)), \(subtitle)"
        guard let response = meal.response else {
            return "\(head). " + String(localized: "reports.meal.noResponse", defaultValue: "Sin lecturas suficientes después para medir la respuesta.")
        }
        let back = response.returnMinutes.map {
            String(localized: "reports.meal.return.a11y", defaultValue: "volvió a su nivel en \(ReportFormat.duration(minutes: $0))")
        } ?? String(localized: "reports.meal.noReturn.a11y", defaultValue: "no volvió a su nivel en 3 horas")
        return String(
            localized: "reports.meal.row.a11y",
            defaultValue: "\(head). Subió \(Int(response.rise.rounded())) hasta \(response.peak) miligramos por decilitro en \(response.timeToPeakMinutes) minutos; \(back).")
    }
}
