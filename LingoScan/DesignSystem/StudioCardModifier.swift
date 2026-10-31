import SwiftUI

/// Card sólida Studio: relleno casi opaco y tinte opcional en diagonal.
/// En oscuro, filo de luz superior; en claro (T-30), borde fino y sombra suave, porque un filo blanco no se ve
/// sobre blanco. Con Reducir transparencia el relleno es opaco en las dos variantes.
struct StudioCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color?
    var radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let isLight = colorScheme == .light
        content
            .background {
                shape.fill(Tokens.Studio.card.opacity(Tokens.Studio.cardOpacity(reduceTransparency: reduceTransparency)))
                    .shadow(color: Tokens.Studio.shadow, radius: isLight ? 10 : 0, y: isLight ? 3 : 0)
                if let tint {
                    shape.fill(LinearGradient(
                        colors: [tint.opacity(isLight ? 0.12 : 0.18), tint.opacity(isLight ? 0.03 : 0.04), .clear],
                        startPoint: .topLeading, endPoint: .center))
                }
            }
            .overlay {
                // Oscuro: filo de luz superior (el borde "recibe" la luz de arriba) + contorno tintado.
                // Claro: borde fino uniforme (gradiente de un solo color, sin ramas que cambien la identidad).
                shape.strokeBorder(LinearGradient(colors: edgeColors(isLight: isLight),
                                                  startPoint: .top, endPoint: .bottom),
                                   lineWidth: 1)
            }
            .animation(Motion.color, value: tint)
    }

    private func edgeColors(isLight: Bool) -> [Color] {
        if isLight {
            let edge = tint?.opacity(0.30) ?? Tokens.Studio.stroke
            return [edge, edge]
        }
        let base = tint ?? .white
        return [base.opacity(tint == nil ? 0.14 : 0.42), base.opacity(tint == nil ? 0.05 : 0.14)]
    }
}
