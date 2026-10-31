import SwiftUI

/// Materiales del tema Studio (port de JPLights): vidrio Liquid Glass selectivo y cards sólidas, ambos con
/// caída a superficies opacas cuando el usuario activa Reducir transparencia.
///
/// - Vidrio: solo controles flotantes y chips. Lo interactivo es `.clear` con tinte suave; lo informativo `.regular`.
/// - Sólido: cards con texto, gráficas y listas (legibilidad primero).
extension View {
    /// Superficie de card sólida del tema, con tinte opcional (nunca rojo para glucosa).
    func studioCard(tint: Color? = nil, radius: CGFloat = Tokens.Radius.card) -> some View {
        modifier(StudioCardModifier(tint: tint, radius: radius))
    }

    /// Vidrio Liquid Glass con forma; opaco con Reducir transparencia. Agrupar varios en `GlassEffectContainer`.
    func studioGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(StudioGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}
