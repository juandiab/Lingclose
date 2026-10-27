import SwiftUI

/// Selector 3 h / 6 h / 12 h / 24 h con chips de vidrio agrupados en un único contenedor.
/// En un día anterior la curva muestra el día completo y los chips quedan deshabilitados.
struct PeriodPicker: View {
    @Binding var period: TodayPeriod
    var isEnabled = true

    var body: some View {
        GlassEffectContainer(spacing: Tokens.Spacing.xs) {
            HStack(spacing: Tokens.Spacing.xs) {
                ForEach(TodayPeriod.allCases) { option in
                    Button {
                        period = option
                    } label: {
                        GlassChip(title: option.title, isSelected: option == period && isEnabled, isInteractive: isEnabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option == period ? .isSelected : [])
                }
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .sensoryFeedback(.selection, trigger: period)
    }
}

#Preview {
    @Previewable @State var period = TodayPeriod.sixHours
    PeriodPicker(period: $period)
        .padding()
}
