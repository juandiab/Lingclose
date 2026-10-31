import CoreGraphics

/// Dedo sobre la pantalla (coordenadas en puntos de la vista del fondo, origen arriba-izquierda).
struct PointerEvent: Sendable {
    enum Phase: Sendable {
        case began, moved, ended, cancelled
    }

    var phase: Phase
    var location: CGPoint
    /// `true` en `.ended` si fue un toque corto y sin desplazamiento.
    var isTap = false
}
