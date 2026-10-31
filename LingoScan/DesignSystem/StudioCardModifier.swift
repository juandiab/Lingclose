import SwiftUI

/// Card sólida Studio: relleno casi opaco, tinte opcional en diagonal y filo de luz superior.
struct StudioCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var tint: Color?
    var radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(Tokens.Studio.card.opacity(Tokens.Studio.cardOpacity(reduceTransparency: reduceTransparency)))
                if let tint {
                    shape.fill(LinearGradient(
                        colors: [tint.opacity(0.18), tint.opacity(0.04), .clear],
                        startPoint: .topLeading, endPoint: .center))
                }
            }
            .overlay {
                // Filo de luz superior (el borde "recibe" la luz de arriba) + contorno tintado.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [(tint ?? .white).opacity(tint == nil ? 0.14 : 0.42),
                                 (tint ?? .white).opacity(tint == nil ? 0.05 : 0.14)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            .animation(Motion.color, value: tint)
    }
}
