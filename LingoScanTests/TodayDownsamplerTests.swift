import Foundation
import Testing
@testable import LingoScan

/// Reducción por cubos de la curva para dibujar (no afecta al cursor, las estadísticas ni los picos).
struct TodayDownsamplerTests {
    private func points(count: Int, from startMinute: Int = 0, session: String = "s") -> [GlucosePoint] {
        (0..<count).map { offset in
            let minute = startMinute + offset
            return GlucosePoint(
                id: "\(session)-\(minute)",
                sessionID: session,
                lifeCount: minute,
                date: Date(timeIntervalSince1970: Double(minute) * 60),
                value: 100 + offset % 7
            )
        }
    }

    @Test func fifteenHundredContinuousPointsUseTwoMinuteBuckets() throws {
        let segments = GlucoseSegmenter.segments(from: points(count: 1_500))
        #expect(segments.count == 1)
        let reduced = GlucoseDownsampler.reduce(segments)
        let drawn = try #require(reduced.first?.points)
        #expect(drawn.count <= GlucoseDownsampler.maxPoints)
        #expect(drawn.count == 750, "cubos de 2 min alineados: dos lecturas por cubo")
        // Media redondeada y fecha media del primer cubo (minutos 0 y 1, valores 100 y 101).
        #expect(drawn[0].value == 101 || drawn[0].value == 100)
        #expect(drawn[0].date == Date(timeIntervalSince1970: 30))
        #expect(zip(drawn, drawn.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    @Test func bucketsNeverCrossAGap() {
        // 700 lecturas, hueco de 30 min y 700 más: dos tramos.
        let raw = points(count: 700) + points(count: 700, from: 730)
        let segments = GlucoseSegmenter.segments(from: raw)
        #expect(segments.count == 2)
        let gap = GlucoseSegmenter.gaps(in: segments)[0]
        let reduced = GlucoseDownsampler.reduce(segments)
        #expect(reduced.count == 2)
        #expect(reduced.map(\.id) == segments.map(\.id))
        #expect(reduced.reduce(0) { $0 + $1.points.count } <= GlucoseDownsampler.maxPoints)
        let all = reduced.flatMap(\.points)
        #expect(!all.contains { $0.date > gap.start && $0.date < gap.end }, "ningún punto reducido cae en el hueco")
        // Cada tramo reducido queda dentro de su tramo crudo.
        for (raw, drawn) in zip(segments, reduced) {
            #expect(drawn.points.allSatisfy { $0.date >= raw.points[0].date && $0.date <= raw.points[raw.points.count - 1].date })
        }
    }

    @Test func fewerThanTheLimitIsUntouched() {
        let segments = GlucoseSegmenter.segments(from: points(count: 899))
        #expect(GlucoseDownsampler.reduce(segments) == segments)
    }

    @Test func largerSeriesPickTheSmallestBucketThatFits() {
        // 3 000 lecturas: 2 min → 1 500 (no cabe), 5 min → 600.
        let segments = GlucoseSegmenter.segments(from: points(count: 3_000))
        let drawn = GlucoseDownsampler.reduce(segments).flatMap(\.points)
        #expect(drawn.count == 600)
    }
}
