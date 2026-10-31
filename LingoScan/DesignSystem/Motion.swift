import SwiftUI

/// Coreografía compartida (port de JPLights): springs únicos para toda la app.
/// Quien anima respeta Reduce Motion (`accessibilityReduceMotion` → sin animación o solo opacidad).
enum Motion {
    /// Controles: píldoras, chips, toggles. Respuesta rápida, sin rebote apreciable.
    static let snappy = Animation.spring(duration: 0.32, bounce: 0.12)
    /// Layout: expandir / colapsar, reordenar, cambiar de panel.
    static let smooth = Animation.spring(duration: 0.45, bounce: 0.04)
    /// Entradas delicadas (banners, resultados).
    static let gentle = Animation.spring(duration: 0.6, bounce: 0.06)
    /// Transiciones de color progresivas (tintes de card).
    static let color = Animation.easeInOut(duration: 0.55)
    /// Pulsación de botones.
    static let press = Animation.spring(duration: 0.22, bounce: 0.18)

    /// La animación pedida, o `nil` con Reduce Motion.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
