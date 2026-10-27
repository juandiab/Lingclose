import LingoCore
import SwiftUI

/// Porciones consumidas sobre la base: 0,5…5,0 en pasos de 0,1 (media porción a cinco); arranca en 1,0, la base. Solo cambia el multiplicador; el
/// recálculo (siempre desde la base) lo hace quien la usa.
struct PortionSlider: View {
    @Binding var multiplier: Double
    /// "1,5" (ya con coma decimal).
    let multiplierText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Text(String(localized: "meal.portions", defaultValue: "Porciones: \(multiplierText) ×"))
                .font(.headline)
                .monospacedDigit()
            Slider(
                value: $multiplier,
                in: NutrientLimits.portionMultiplier,
                step: NutrientLimits.portionStep
            ) {
                Text(String(localized: "meal.portions.label", defaultValue: "Porciones"))
            } minimumValueLabel: {
                Text(NutrientLimits.portionMultiplier.lowerBound, format: .number)
            } maximumValueLabel: {
                Text(NutrientLimits.portionMultiplier.upperBound, format: .number)
            }
            .accessibilityValue(multiplierText)
        }
        .sensoryFeedback(.selection, trigger: multiplierText)
    }
}
