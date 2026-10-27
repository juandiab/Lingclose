import SwiftUI

/// Selector 3 h / 6 h / 24 h con chips de vidrio agrupados en un único contenedor.
struct PeriodPicker: View {
    @Binding var period: TodayPeriod

    var body: some View {
        GlassEffectContainer(spacing: Tokens.Spacing.xs) {
            HStack(spacing: Tokens.Spacing.xs) {
                ForEach(TodayPeriod.allCases) { option in
                    Button {
                        period = option
                    } label: {
                        GlassChip(title: option.title, isSelected: option == period)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option == period ? .isSelected : [])
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var period = TodayPeriod.sixHours
    PeriodPicker(period: $period)
        .padding()
}
