import SwiftUI

/// Contenido del popover de un marcador: tipo, hora, gramos o duración y texto.
struct DiaryMarkDetail: View {
    let mark: DiaryMark

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Label(mark.kind.title, systemImage: mark.kind.systemImage)
                .font(.headline)
            Text(mark.date, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let detail = mark.detail {
                Text(detail)
                    .monospacedDigit()
            }
            if let text = mark.text {
                Text(text)
            }
            if mark.synthetic {
                Text(String(localized: "today.mark.synthetic", defaultValue: "Ejemplo (sintético)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Tokens.Spacing.sm)
        .frame(minWidth: 220, alignment: .leading)
    }
}
