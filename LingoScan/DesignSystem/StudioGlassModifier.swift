import SwiftUI

/// Vidrio Studio. `.glassEffect` va después del layout de quien lo usa; `.interactive()` solo en lo tocable.
struct StudioGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var shape: S
    var tint: Color?
    var interactive: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    shape.fill(Tokens.Studio.raised)
                    if let tint { shape.fill(tint.opacity(0.35)) }
                }
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
        } else {
            // Interactivo → `.clear` (se ve el fondo refractado). Informativo → `.regular` (legibilidad).
            content.glassEffect(
                (interactive ? Glass.clear : Glass.regular)
                    .tint(tint?.opacity(Tokens.Studio.glassTintCap))
                    .interactive(interactive),
                in: shape)
        }
    }
}
