import SwiftUI

/// Cabecera de Hoy: `‹ Hoy ▾ ›` con selector de fecha en un popover compacto.
struct DayNavigator: View {
    let viewModel: TodayViewModel
    @State private var isPickingDate = false
    @State private var pickedDate = Date.now

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Button(String(localized: "today.day.previous", defaultValue: "Día anterior"), systemImage: "chevron.left") {
                viewModel.goBack()
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)

            Button {
                pickedDate = viewModel.shownDay
                isPickingDate = true
            } label: {
                HStack(spacing: Tokens.Spacing.xxs) {
                    Text(title)
                        .font(.headline)
                        .contentTransition(.interpolate)
                    Image(systemName: "chevron.down")
                        .font(.caption2.bold())
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(String(localized: "today.day.pick.hint", defaultValue: "Elige otra fecha"))
            .popover(isPresented: $isPickingDate) {
                DatePicker(
                    String(localized: "today.day.pick", defaultValue: "Fecha"),
                    selection: $pickedDate,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(Tokens.Spacing.sm)
                .frame(minWidth: 320)
                .presentationCompactAdaptation(.popover)
                .onChange(of: pickedDate) { _, newValue in
                    viewModel.select(day: newValue)
                    isPickingDate = false
                }
            }

            Button(String(localized: "today.day.next", defaultValue: "Día siguiente"), systemImage: "chevron.right") {
                viewModel.goForward()
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!viewModel.canGoForward)
        }
        .sensoryFeedback(.selection, trigger: viewModel.dayOffset)
    }

    private var title: String {
        switch viewModel.dayOffset {
        case 0: String(localized: "today.day.today", defaultValue: "Hoy")
        case -1: String(localized: "today.day.yesterday", defaultValue: "Ayer")
        default: viewModel.shownDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }
}
