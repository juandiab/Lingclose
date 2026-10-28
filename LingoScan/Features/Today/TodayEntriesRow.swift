import SwiftUI

/// Fila delgada "Registro de hoy: N", que lleva a la pestaña Diario.
struct TodayEntriesRow: View {
    let count: Int
    let isToday: Bool

    @Environment(\.tabSelector) private var tabSelector

    var body: some View {
        Button {
            tabSelector(.diary)
        } label: {
            HStack(spacing: Tokens.Spacing.xs) {
                Image(systemName: "book.closed")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.bold())
                    .monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: Tokens.Radius.card))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "today.entries.hint.diary", defaultValue: "Abre la pestaña Diario para ver y editar los registros"))
    }

    private var title: String {
        isToday
            ? String(localized: "today.entries.today", defaultValue: "Registro de hoy: \(count)")
            : String(localized: "today.entries.day", defaultValue: "Registro del día: \(count)")
    }
}
