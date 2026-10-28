import SwiftUI

/// Atajos 3 h / 6 h / 12 h / 24 h con chips de vidrio agrupados en un único contenedor.
/// Un chip aparece seleccionado solo cuando la longitud visible coincide con él (±1 min); tras un
/// pellizco libre ninguno lo está.
struct PeriodPicker: View {
    let viewModel: TodayViewModel
    let onSelect: (TodayPeriod) -> Void

    /// Se lee aquí (y no en `TodayView`) para que el pellizco solo redibuje los chips.
    private var selected: TodayPeriod? { viewModel.period }

    var body: some View {
        GlassEffectContainer(spacing: Tokens.Spacing.xs) {
            HStack(spacing: Tokens.Spacing.xs) {
                ForEach(TodayPeriod.allCases) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        GlassChip(title: option.title, isSelected: option == selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option == selected ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
    }
}

#Preview {
    let data = PreviewData()
    let model = TodayViewModel(dataSource: data, sensorSource: data)
    PeriodPicker(viewModel: model) { model.setVisibleLength($0.duration) }
        .padding()
}
