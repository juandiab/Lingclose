import SwiftUI

/// Fila "Registro de hoy: N" con acceso a la lista del día.
struct TodayEntriesRow: View {
    let count: Int
    let isToday: Bool

    var body: some View {
        NavigationLink(value: TodayRoute.entries) {
            Card {
                HStack(spacing: Tokens.Spacing.sm) {
                    Image(systemName: "book.closed")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.headline)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.bold())
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 28)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "today.entries.hint", defaultValue: "Abre los registros del día para editarlos"))
    }

    private var title: String {
        isToday
            ? String(localized: "today.entries.today", defaultValue: "Registro de hoy: \(count)")
            : String(localized: "today.entries.day", defaultValue: "Registro del día: \(count)")
    }
}
