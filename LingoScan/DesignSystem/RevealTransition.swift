import SwiftUI

/// Entrada/salida delicada: opacidad + desenfoque + escala 0,98 desde arriba. Con Reduce Motion, solo opacidad.
struct RevealTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(RevealEffect(hidden: !phase.isIdentity))
    }
}

private struct RevealEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .blur(radius: hidden && !reduceMotion ? 8 : 0)
            .scaleEffect(hidden && !reduceMotion ? 0.98 : 1, anchor: .top)
    }
}

extension Transition where Self == RevealTransition {
    static var reveal: RevealTransition { RevealTransition() }
}
