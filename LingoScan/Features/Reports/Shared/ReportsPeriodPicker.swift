import LingoCore
import SwiftUI

/// Selector 7 / 14 / 30 / 90 días: cápsulas de vidrio interactivas en un único contenedor; la elegida, teñida.
struct ReportsPeriodPicker: View {
    let selection: ReportPeriod.Preset
    let onSelect: (ReportPeriod.Preset) -> Void

    var body: some View {
        GlassEffectContainer(spacing: Tokens.Spacing.xs) {
            HStack(spacing: Tokens.Spacing.xs) {
                ForEach(ReportPeriod.Preset.allCases, id: \.self) { preset in
                    let isSelected = preset == selection
                    Button {
                        onSelect(preset)
                    } label: {
                        Text(String(localized: "reports.period.short", defaultValue: "\(preset.days) d"))
                            .font(.subheadline)
                            .bold(isSelected)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.capsule)
                            .studioGlass(Capsule(), tint: isSelected ? Tokens.Studio.accent : nil, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "reports.period.a11y", defaultValue: "Últimos \(preset.days) días"))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

#Preview {
    ReportsPeriodPicker(selection: .days14) { _ in }
        .padding()
}
