import CoreGraphics

/// Datos de un frame que `BackgroundEngine` entrega al renderer activo.
struct BackgroundFrame {
    /// Tamaño del drawable en píxeles.
    var drawableSize: CGSize
    /// Píxeles por punto del drawable (≤ escala de pantalla, según calidad).
    var scale: CGFloat
    /// Segundos reales desde el frame anterior (acotado a 1/10 s).
    var dt: Float
    /// 0 = Reduce Motion (todo quieto), 1 = normal.
    var motion: Float
    var frameIndex: UInt32
    var quality: RenderQuality
}
