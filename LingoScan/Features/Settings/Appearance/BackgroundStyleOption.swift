import SwiftUI

/// Una opción del selector de fondo: miniatura + nombre; la seleccionada lleva un borde de acento.
struct BackgroundStyleOption: View {
    let style: BackgroundStyle
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            VStack(spacing: Tokens.Spacing.xs) {
                BackgroundThumbnail(style: style)
                    .frame(height: 72)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(.white.opacity(0.10), lineWidth: 1) }
                    .overlay {
                        if isSelected {
                            shape.strokeBorder(Color.accentColor, lineWidth: 2)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                Text(style.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
