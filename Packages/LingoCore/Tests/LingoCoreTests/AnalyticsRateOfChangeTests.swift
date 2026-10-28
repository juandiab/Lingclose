import Testing
@testable import LingoCore

struct AnalyticsRateOfChangeTests {
    private typealias S = AnalyticsSeries

    /// 30 min planos en 100, subida de 2,5 mg/dL/min durante 20 min (hasta 150) y 30 min planos.
    private func ramp(perMinute rate: Double, minutes: Int = 20, from base: Double = 100) -> [BasicStats.Sample] {
        S.series(0...(60 + minutes)) { m in
            if m <= 30 { return base }
            if m <= 30 + minutes { return base + Double(m - 30) * rate }
            return base + Double(minutes) * rate
        }
    }

    @Test func fastRiseIsDetectedAndTrimmedToTheExcursion() throws {
        let events = RateOfChange.events(in: ramp(perMinute: 2.5))
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.direction == .rising)
        #expect(event.start == S.instant(30))
        #expect(event.end == S.instant(50))
        #expect(event.from == 100)
        #expect(event.to == 150)
        #expect(abs(event.slopePerMinute - 2.5) < 1e-9)
    }

    @Test func slowRiseIsNotAnEvent() {
        #expect(RateOfChange.events(in: ramp(perMinute: 1.0)).isEmpty)
    }

    @Test func fastFallIsDetected() throws {
        let events = RateOfChange.events(in: ramp(perMinute: -3, minutes: 15, from: 160))
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.direction == .falling)
        #expect(event.from == 160)
        #expect(event.to == 115)
        #expect(event.slopePerMinute < -2)
    }

    @Test func shortBurstUnderTenMinutesIsDiscarded() {
        // 3 mg/dL/min durante 6 min: la pendiente de alguna ventana pasa del umbral, pero el episodio dura < 10 min.
        #expect(RateOfChange.events(in: ramp(perMinute: 3, minutes: 6)).isEmpty)
    }

    @Test func gapsAreNotBridged() {
        // Dos tramos planos a 100 y 160 separados por 30 min sin lecturas: no es una subida.
        let samples = S.series(0...20) { _ in 100 } + S.series(50...70) { _ in 160 }
        #expect(RateOfChange.events(in: samples).isEmpty)
    }

    @Test func consecutiveWindowsMergeIntoOneEpisode() {
        // Subida larga (40 min a 2,5/min): una sola entrada, no una por ventana.
        let events = RateOfChange.events(in: ramp(perMinute: 2.5, minutes: 40))
        #expect(events.count == 1)
        #expect(events.first?.duration == Int64(40 * 60))
    }

    @Test func regressionSlope() {
        let samples = S.series(0...14) { 100 + Double($0) * 2 }
        #expect(abs((RateOfChange.slope(of: samples) ?? 0) - 2) < 1e-9)
        #expect(RateOfChange.slope(of: Array(samples.prefix(1))) == nil)
        #expect(RateOfChange.events(in: []).isEmpty)
    }
}
