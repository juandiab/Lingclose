import Testing
@testable import LingoCore

struct BasicStatsTests {
    static let t0 = UTCInstant(epochSeconds: TestSupport.activationEpoch)

    private func sample(_ minute: Int, _ value: Int) -> BasicStats.Sample {
        BasicStats.Sample(measuredAt: Self.t0.adding(seconds: Int64(minute) * 60), valueMgdl: value)
    }

    // MARK: Fixture 1: huecos (no se interpola; la fracción es de lecturas válidas)

    @Test func gapsAreNotInterpolated() throws {
        // 0..4 en 100, hueco de 55 min, 60..64 en 200: 10 lecturas, 5 dentro de 70-180.
        let samples = (0..<5).map { sample($0, 100) } + (60..<65).map { sample($0, 200) }
        let window = Self.t0...Self.t0.adding(seconds: 64 * 60)
        let stats = BasicStats(samples: samples, window: window)
        #expect(stats.count == 10)
        #expect(stats.mean == 150)
        #expect(stats.timeInRange == 0.5)
        // SD muestral: sum (x-150)^2 = 10 * 2500 = 25000; / 9 -> 52.7046...
        let sd = try #require(stats.standardDeviation)
        #expect(abs(sd - (25_000.0 / 9).squareRoot()) < 1e-9)
        // Cobertura: 10 lecturas de 65 minutos posibles.
        let coverage = try #require(stats.coverage)
        #expect(abs(coverage - 10.0 / 65) < 1e-9)
    }

    // MARK: Fixture 2: calentamiento (lecturas excluidas no cuentan)

    @Test func warmupReadingsAreIgnored() throws {
        let session = TestSupport.session(warmup: 60)
        var readings: [GlucoseReading] = []
        for lc in 55..<65 {
            // 55..59 caen en calentamiento (excluidas, sin valor); 60..64 son elegibles con 120.
            readings.append(TestSupport.reading(session, lc: lc, raw: TestSupport.raw(uncapped: 120, capped: 120), origin: .live))
        }
        let excluded = readings.filter { !$0.eligibility.isEligible }
        #expect(excluded.count == 5)
        let stats = BasicStats(readings: readings)
        #expect(stats.count == 5)
        #expect(stats.mean == 120)
        #expect(stats.standardDeviation == 0)
        #expect(stats.timeInRange == 1)
    }

    // MARK: Fixture 3: vacío

    @Test func emptyHasNoMetrics() {
        let stats = BasicStats(samples: [], window: Self.t0...Self.t0.adding(seconds: 3_600))
        #expect(stats.count == 0)
        #expect(stats.mean == nil)
        #expect(stats.standardDeviation == nil)
        #expect(stats.timeInRange == nil)
        #expect(stats.coverage == 0)
    }

    @Test func singleReadingHasNoStandardDeviation() {
        let stats = BasicStats(samples: [sample(0, 190)])
        #expect(stats.mean == 190)
        #expect(stats.standardDeviation == nil)
        #expect(stats.timeInRange == 0)
    }

    // MARK: Fixture 4: 24 h completas

    @Test func fullDayWithRangeEdges() throws {
        // 1440 minutos: 360 en 70 (borde inclusivo), 360 en 180 (borde inclusivo), 360 en 69, 360 en 181.
        var samples: [BasicStats.Sample] = []
        for minute in 0..<1_440 {
            let value = [70, 180, 69, 181][minute / 360]
            samples.append(sample(minute, value))
        }
        let window = Self.t0...Self.t0.adding(seconds: 1_439 * 60)
        let stats = BasicStats(samples: samples, window: window)
        #expect(stats.count == 1_440)
        #expect(stats.timeInRange == 0.5)
        #expect(stats.mean == 125)
        let squares: Double = 55 * 55 + 55 * 55 + 56 * 56 + 56 * 56
        let expectedSD = (360.0 * squares / 1_439.0).squareRoot()
        let sd = try #require(stats.standardDeviation)
        #expect(abs(sd - expectedSD) < 1e-9)
        #expect(stats.coverage == 1)
    }

    @Test func duplicatesAtTheSameInstantCountOnce() {
        let stats = BasicStats(samples: [sample(0, 100), sample(0, 100), sample(1, 140)])
        #expect(stats.count == 2)
        #expect(stats.mean == 120)
    }
}
