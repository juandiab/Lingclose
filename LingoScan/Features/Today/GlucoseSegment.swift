import Foundation

/// Tramo continuo de la curva. Entre tramos no se dibuja línea: el hueco es visible.
struct GlucoseSegment: Sendable, Hashable, Identifiable {
    let id: Int
    let points: [GlucosePoint]
}
