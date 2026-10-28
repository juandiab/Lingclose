import Foundation

/// Parte la serie en tramos continuos.
///
/// Se corta cuando cambia la sesión o cuando pasan más de `maxInterval` segundos entre dos puntos.
/// Un minuto perdido por Bluetooth (`life_count` no consecutivo pero poco tiempo) no corta el trazo: la
/// línea une los dos puntos (D-24). Solo una ausencia larga queda como hueco abierto, sin interpolar.
enum GlucoseSegmenter {
    /// Quince minutos: pérdidas cortas de paquetes BLE se unen; más allá es un hueco real.
    static let maxInterval: TimeInterval = 15 * 60

    static func segments(from points: [GlucosePoint], maxInterval: TimeInterval = maxInterval) -> [GlucoseSegment] {
        let sorted = points.sorted { $0.date < $1.date }
        var segments: [GlucoseSegment] = []
        var current: [GlucosePoint] = []
        for point in sorted {
            if let previous = current.last, isBreak(from: previous, to: point, maxInterval: maxInterval) {
                segments.append(GlucoseSegment(id: segments.count, points: current))
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty {
            segments.append(GlucoseSegment(id: segments.count, points: current))
        }
        return segments
    }

    /// Huecos entre tramos consecutivos: del último punto de uno al primero del siguiente.
    static func gaps(in segments: [GlucoseSegment]) -> [GlucoseGap] {
        zip(segments, segments.dropFirst()).compactMap { before, after in
            guard let end = before.points.last?.date, let start = after.points.first?.date else { return nil }
            return GlucoseGap(start: end, end: start)
        }
    }

    private static func isBreak(from previous: GlucosePoint, to next: GlucosePoint, maxInterval: TimeInterval) -> Bool {
        previous.sessionID != next.sessionID
            || next.date.timeIntervalSince(previous.date) > maxInterval
    }
}
