import SwiftUI

/// Rejilla adaptable de estadísticas: 2–4 columnas según el ancho y el tamaño de letra.
struct ReportStatGrid<Content: View>: View {
    @ScaledMetric(relativeTo: .title3) private var minimumWidth = 96.0
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: Tokens.Spacing.sm, alignment: .topLeading)],
            alignment: .leading,
            spacing: Tokens.Spacing.sm
        ) {
            content
        }
    }
}
