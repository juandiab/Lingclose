import CoreGraphics

/// Agrupa elementos de la curva por cercanía horizontal en pantalla (marcadores e índices de pico).
/// Depende de las posiciones en puntos, así que se recalcula con cada zoom o desplazamiento.
enum ChartXGrouping {
    /// Grupos en orden de `x`: un elemento entra en el grupo del anterior si su `x` queda a menos de
    /// `minDistance` puntos de la del anterior (encadenado); si no, abre un grupo nuevo.
    static func groups<ID: Hashable>(_ items: [(x: CGFloat, id: ID)], minDistance: CGFloat) -> [[ID]] {
        let sorted = items.sorted { $0.x < $1.x }
        var result: [[ID]] = []
        var previousX: CGFloat?
        for item in sorted {
            if let previousX, item.x - previousX < minDistance, !result.isEmpty {
                result[result.count - 1].append(item.id)
            } else {
                result.append([item.id])
            }
            previousX = item.x
        }
        return result
    }
}
