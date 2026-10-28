import SwiftUI

/// Fila de la hoja de insights: nombre y hora de la comida y su respuesta de glucosa.
struct MealInsightRow: View {
    let meal: TodayMealInsight

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Label(meal.name, systemImage: DiaryMark.Kind.meal.systemImage)
                    .font(.headline)
                Spacer(minLength: Tokens.Spacing.xs)
                Text(meal.mark.date, format: .dateTime.hour().minute())
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            MealResponseSummary(response: meal.response)
                .font(.subheadline)
        }
        .padding(.vertical, Tokens.Spacing.xxs)
    }
}
