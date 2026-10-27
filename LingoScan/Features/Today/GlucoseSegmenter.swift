import Foundation

/// Parte la serie en tramos continuos. Nunca interpola.
///
/// Se corta cuando cambia la sesión, cuando `life_count` no es consecutivo o cuando pasan
/// más de `maxInterval` segundos entre dos puntos.
enum GlucoseSegmenter {
    /// Dos minutos: un `life_count` por minuto más un margen.
    static let maxInterval: TimeInterval = 120

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
            || next.lifeCount != previous.lifeCount + 1
            || next.date.timeIntervalSince(previous.date) > maxInterval
    }
}
