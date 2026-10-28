import SwiftUI

/// Marcador de comida o ejercicio sobre la curva. Con varias marcas cercanas muestra el icono de la primera,
/// una insignia con el número de marcas y la hora de la primera; el popover las lista todas.
struct ChartMarkGroupButton: View {
    let group: ChartMarkGroup
    @State private var isShowingDetail = false

    var body: some View {
        Button(action: showDetail) {
            VStack(spacing: 0) {
                Image(systemName: group.first.kind.systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: .circle)
                    .overlay(alignment: .topTrailing) {
                        if group.marks.count > 1 {
                            Text(group.marks.count, format: .number)
                                .font(.caption2.bold())
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(.red, in: .capsule)
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(group.first.date, format: .dateTime.hour().minute())
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(String(localized: "today.mark.hint", defaultValue: "Muestra el detalle"))
        .popover(isPresented: $isShowingDetail) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.marks) { mark in
                        if mark.id != group.first.id { Divider() }
                        DiaryMarkDetail(mark: mark)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var accessibilityText: String {
        let items = group.marks
            .map { "\($0.kind.title), \($0.date.formatted(date: .omitted, time: .shortened))" }
            .joined(separator: "; ")
        guard group.marks.count > 1 else { return items }
        return String(localized: "today.mark.group.a11y", defaultValue: "\(group.marks.count) marcas: \(items)")
    }

    private func showDetail() {
        isShowingDetail = true
    }
}
