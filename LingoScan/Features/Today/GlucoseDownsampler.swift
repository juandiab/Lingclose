import Foundation

/// Reducción por cubos de tiempo para **dibujar** la curva. Con lecturas cada minuto y el búfer de carga,
/// 24 h visibles son hasta 4 320 puntos (y tres marcas por punto); por encima de `maxPoints` se agrupan
/// en cubos de 2, 5 o 10 min (el menor que deje `maxPoints` o menos).
///
/// Cada cubo da un punto con la media redondeada y la fecha media de sus lecturas. Los cubos nunca cruzan
/// un corte de tramo: los huecos se conservan. La lectura del cursor, las estadísticas y los picos siguen
/// usando los puntos crudos.
enum GlucoseDownsampler {
    static let maxPoints = 900
    /// Tamaños de cubo probados, en segundos, de menor a mayor.
    static let bucketSizes: [TimeInterval] = [120, 300, 600]

    /// Tramos listos para dibujar. Sin cambios si el total no supera `maxPoints`.
    static func reduce(_ segments: [GlucoseSegment], maxPoints: Int = maxPoints) -> [GlucoseSegment] {
        let total = segments.reduce(0) { $0 + $1.points.count }
        guard total > maxPoints else { return segments }
        var reduced = segments
        for size in bucketSizes {
            reduced = segments.map { GlucoseSegment(id: $0.id, points: bucketed($0.points, size: size)) }
            if reduced.reduce(0, { $0 + $1.points.count }) <= maxPoints { break }
        }
        return reduced
    }

    /// Un punto por cubo de `size` segundos alineado a la época; `points` ya está ordenado.
    static func bucketed(_ points: [GlucosePoint], size: TimeInterval) -> [GlucosePoint] {
        var result: [GlucosePoint] = []
        result.reserveCapacity(points.count / max(1, Int(size / 60)) + 1)
        var bucket: [GlucosePoint] = []
        var currentKey: Int?
        func flush() {
            guard let first = bucket.first else { return }
            let count = Double(bucket.count)
            let meanValue = (Double(bucket.reduce(0) { $0 + $1.value }) / count).rounded()
            let meanTime = bucket.reduce(0) { $0 + $1.date.timeIntervalSince1970 } / count
            result.append(GlucosePoint(
                id: first.id,
                sessionID: first.sessionID,
                lifeCount: first.lifeCount,
                date: Date(timeIntervalSince1970: meanTime),
                value: Int(meanValue)
            ))
            bucket.removeAll(keepingCapacity: true)
        }
        for point in points {
            let key = Int((point.date.timeIntervalSince1970 / size).rounded(.down))
            if key != currentKey { flush(); currentKey = key }
            bucket.append(point)
        }
        flush()
        return result
    }
}
