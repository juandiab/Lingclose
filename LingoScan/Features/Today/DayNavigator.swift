import SwiftUI

/// Cabecera de Hoy: `‹ Hoy ▾ ›`. El título es el día del fin de la ventana visible; ‹ › la mueven un día
/// conservando la longitud visible; el selector de fecha la coloca para que termine a la misma hora del
/// reloj de ese día (acotada a ahora).
struct DayNavigator: View {
    let viewModel: TodayViewModel
    @State private var isPickingDate = false
    @State private var pickedDate = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Button(String(localized: "today.day.previous", defaultValue: "Día anterior"), systemImage: "chevron.left", action: goBack)
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

            Button(String(localized: "today.day.next", defaultValue: "Día siguiente"), systemImage: "chevron.right", action: goForward)
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!viewModel.canGoForward)
        }
        .sensoryFeedback(.selection, trigger: viewModel.shownDay)
    }

    private var animation: Animation? { reduceMotion ? nil : .snappy }

    private func goBack() {
        withAnimation(animation) { viewModel.goBack() }
    }

    private func goForward() {
        withAnimation(animation) { viewModel.goForward() }
    }

    private var title: String {
        let calendar = viewModel.calendar
        let today = calendar.startOfDay(for: viewModel.now)
        let days = calendar.dateComponents([.day], from: viewModel.shownDay, to: today).day ?? 0
        switch days {
        case 0: return String(localized: "today.day.today", defaultValue: "Hoy")
        case 1: return String(localized: "today.day.yesterday", defaultValue: "Ayer")
        default: return viewModel.shownDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }
}
