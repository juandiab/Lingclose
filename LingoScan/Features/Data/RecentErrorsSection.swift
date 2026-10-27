import SwiftUI

/// Avisos y errores recientes del `event_log` (ya redactados: sin claves ni seriales completos).
struct RecentErrorsSection: View {
    let viewModel: DataViewModel

    var body: some View {
        Section {
            if viewModel.recentErrors.isEmpty {
                Label(String(localized: "data.errors.none", defaultValue: "Sin errores recientes"), systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.recentErrors, id: \.id) { entry in
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    HStack {
                        Text(verbatim: entry.category)
                            .font(.caption.monospaced())
                        Spacer(minLength: Tokens.Spacing.xs)
                        Text(entry.at.date, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    Text(verbatim: entry.message)
                        .font(.footnote)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(String(localized: "data.errors.header", defaultValue: "Errores recientes"))
        }
    }
}
