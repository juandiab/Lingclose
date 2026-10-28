import LingoCore
import SwiftUI

/// Respuesta a una comida: frase con subida, pico y vuelta, y la puntuación informativa en una barra.
struct MealResponseSummary: View {
    let response: MealResponse

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text(InsightFormat.mealSummary(response))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "today.insight.score", defaultValue: "Puntuación \(response.score)/100 (informativa)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            ProgressView(value: Double(response.score), total: 100)
                .tint(Self.tint(for: response.score))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Verde de "en rango" con puntuación alta; ámbar en medio; el color de "alto" por debajo de 40.
    static func tint(for score: Int) -> Color {
        switch score {
        case 70...: Tokens.Palette.inRange
        case 40..<70: Tokens.Palette.outOfRange
        default: Tokens.Palette.high
        }
    }
}
