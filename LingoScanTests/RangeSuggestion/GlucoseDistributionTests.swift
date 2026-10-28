import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// Percentiles, cobertura y propuesta estadística acotada.
struct GlucoseDistributionTests {
    private func samples(_ values: [Int], minuteStep: Int64 = 60) -> [BasicStats.Sample] {
        values.enumerated().map { BasicStats.Sample(measuredAt: UTCInstant(epochSeconds: Int64($0.offset) * minuteStep), valueMgdl: $0.element) }
    }

    @Test func percentilesInterpolateLinearly() {
        let d = GlucoseDistribution(samples: samples([10, 20, 30, 40, 50]))
        #expect(d.percentile(0) == 10)
        #expect(d.percentile(100) == 50)
        #expect(d.percentile(50) == 30)
        #expect(d.percentile(25) == 20)
        #expect(d.percentile(5) == 12)      // posición 0,2 entre 10 y 20
        #expect(d.percentile(95) == 48)     // posición 3,8 entre 40 y 50
        #expect(d.median == 30)
        #expect(d.minimum == 10)
        #expect(d.maximum == 50)
    }

    @Test func emptyAndSingleSampleEdges() {
        let empty = GlucoseDistribution(samples: [])
        #expect(empty.count == 0)
        #expect(empty.percentile(5) == nil)
        #expect(empty.mean == nil)
        #expect(empty.coveredMinutes == 0)
        let one = GlucoseDistribution(samples: samples([99]))
        #expect(one.percentile(5) == 99)
        #expect(one.percentile(95) == 99)
        #expect(one.standardDeviation == nil)
        #expect(one.percentile(101) == nil)
    }

    @Test func coverageCountsDistinctMinutesAndDeduplicatesInstants() {
        var list = samples([100, 100, 100], minuteStep: 60)
        list.append(BasicStats.Sample(measuredAt: UTCInstant(epochSeconds: 0), valueMgdl: 250))  // repetido: se ignora
        list.append(BasicStats.Sample(measuredAt: UTCInstant(epochSeconds: 30), valueMgdl: 100)) // mismo minuto que el primero
        let d = GlucoseDistribution(samples: list)
        #expect(d.count == 4)
        #expect(d.coveredMinutes == 3)
        #expect(d.maximum == 100, "la lectura repetida del instante 0 no cuenta")
    }

    @Test func readingsInitializerSkipsSyntheticExcludedAndDeleted() {
        var readings = RangeFixtures.readings(hours: 1)
        readings[0].synthetic = true
        readings[1].deleted = true
        let flagged = RawReading(capped: 400, uncapped: 400, trend: 0, qualityFlag: true, channel: 1)
        readings.append(GlucoseReading.make(session: RangeFixtures.session, lifeCount: 5, raw: flagged, origin: .live,
                                            receivedAt: UTCInstant(epochSeconds: RangeFixtures.activation + 301), tzAtCapture: RangeFixtures.tz))
        let d = GlucoseDistribution(readings: readings)
        #expect(d.count == 58)
        #expect(d.maximum ?? 0 < 400)
    }

    @Test func statisticalProposalRoundsClampsAndKeepsTheGap() {
        #expect(RangeSuggestionPolicy.statisticalProposal(percentile5: 73.4, percentile95: 146.2) == (75, 145))
        #expect(RangeSuggestionPolicy.statisticalProposal(percentile5: 72.4, percentile95: 147.6) == (70, 150))
        #expect(RangeSuggestionPolicy.statisticalProposal(percentile5: 38, percentile95: 300) == (50, 250), "acotado 50–100 / 100–250")
        #expect(RangeSuggestionPolicy.statisticalProposal(percentile5: 118, percentile95: 121) == (100, 120), "baja ≤ 100 y 20 de separación")
        #expect(RangeSuggestionPolicy.statisticalProposal(percentile5: 96, percentile95: 104) == (95, 115), "sube la alta hasta 20 por encima")
        let edge = RangeSuggestionPolicy.statisticalProposal(percentile5: 100, percentile95: 100)
        #expect(RangeSuggestionBounds.isValid(low: edge.low, high: edge.high))
    }

    @Test func windowIsFourteenDays() {
        let window = RangeSuggestionPolicy.window(endingAt: RangeFixtures.now)
        #expect(window.upperBound.epochSeconds - window.lowerBound.epochSeconds == 14 * 86_400)
    }
}
