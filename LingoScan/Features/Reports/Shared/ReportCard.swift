import SwiftUI

/// Card de un reporte: cabecera con icono, título y, si abre detalle, un chevron; subtítulo opcional y contenido.
struct ReportCard<Content: View>: View {
    let title: String
    let systemImage: String
    var caption: String?
    var showsDisclosure = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xs) {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: systemImage)
                            .foregroundStyle(.secondary)
                    }
                    .font(.headline)
                    Spacer(minLength: Tokens.Spacing.xs)
                    if showsDisclosure {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(Tokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reportSurface()
        .contentShape(.rect(cornerRadius: Tokens.Radius.card))
    }
}

#Preview {
    ReportCard(title: "Resumen", systemImage: "square.grid.2x2", caption: "25–31 oct", showsDisclosure: true) {
        Text(verbatim: "Contenido")
    }
    .padding()
}
