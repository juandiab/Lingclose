import LingoCore
import SwiftUI

/// Subida, pico y retorno de una comida en una fila de cifras pequeñas.
struct MealResponseFacts: View {
    let response: MealResponseReport.Response

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
            fact(String(localized: "reports.meal.rise", defaultValue: "Subida"), ReportFormat.signed(response.rise))
            fact(String(localized: "reports.meal.peak", defaultValue: "Pico"), "\(response.peak)")
            fact(
                String(localized: "reports.meal.return", defaultValue: "Volvió"),
                response.returnMinutes.map { ReportFormat.duration(minutes: $0) }
                    ?? String(localized: "reports.meal.noReturn", defaultValue: "> 3 h"))
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
    }
}
