import Foundation
import Testing
import LingoCore
@testable import LingoScan

@MainActor
struct TodayViewModelTests {
    /// Instante fijo para que las lecturas sintéticas sean deterministas.
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(sensorState: SensorPresentationState = .streaming) -> (TodayViewModel, PreviewData) {
        let data = PreviewData(now: Self.now, sensorState: sensorState)
        let model = TodayViewModel(dataSource: data, sensorSource: data, clock: { Self.now })
        return (model, data)
    }

    // MARK: Último valor elegible

    @Test func latestEligibleIsTheNewestValidReading() async throws {
        let (model, data) = makeModel()
        await model.refresh()
        let latest = try #require(model.latest)
        #expect(latest.eligibility.isEligible)
        #expect(latest.synthetic)
        #expect(latest.measuredAt.date == Self.now.addingTimeInterval(-Double(PreviewData.latestAgeMinutes) * 60))
        #expect(model.latestValue == latest.value)
        // Ninguna lectura elegible es más nueva.
        let newestEligible = data.readings.filter { $0.eligibility.isEligible }.map(\.measuredAt).max()
        #expect(latest.measuredAt == newestEligible)
    }

    @Test func excludedReadingsNeverBecomeTheLatestValue() async throws {
        let (model, data) = makeModel()
        await model.refresh()
        let excluded = data.readings.filter { !$0.eligibility.isEligible }
        #expect(!excluded.isEmpty)
        #expect(excluded.allSatisfy { $0.value == nil })
        let latest = try #require(model.latest)
        #expect(!excluded.contains { $0.recordID == latest.recordID })
        #expect(!model.points.contains { point in excluded.contains { $0.recordID == point.id } })
    }

    @Test func ageAndStaleness() async {
        let (model, _) = makeModel()
        await model.refresh()
        #expect(model.ageMinutes(at: Self.now) == PreviewData.latestAgeMinutes)
        #expect(!model.isStale(at: Self.now))
        #expect(model.isStale(at: Self.now.addingTimeInterval(4 * 60)))
        #expect(!model.isStale(at: Self.now.addingTimeInterval(2 * 60)))
    }

    // MARK: Huecos

    @Test func sixHourWindowHasOneVisibleGapOfTwentySixMinutes() async throws {
        let (model, _) = makeModel()
        model.period = .sixHours
        await model.refresh()
        #expect(model.segments.count == 2)
        let gap = try #require(model.gaps.first)
        #expect(model.gaps.count == 1)
        // 25 lecturas ausentes: del último punto antes del corte al primero después hay 26 minutos.
        #expect(gap.duration == Double(PreviewData.disconnectionMinutes + 1) * 60)
        // Ninguna serie atraviesa el hueco.
        let allPoints = model.points
        #expect(!allPoints.contains { $0.date > gap.start && $0.date < gap.end })
    }

    @Test func twentyFourHourWindowAlsoShowsTheQualityFlagGap() async {
        let (model, _) = makeModel()
        model.period = .twentyFourHours
        await model.refresh()
        #expect(model.gaps.count == 2)
        #expect(model.segments.count == 3)
        let durations = model.gaps.map(\.duration).sorted()
        #expect(durations == [Double(PreviewData.qualityFlagCount + 1) * 60, Double(PreviewData.disconnectionMinutes + 1) * 60])
    }

    @Test func segmenterBreaksOnNonConsecutiveLifeCount() {
        let points = [
            point(lifeCount: 10, seconds: 0),
            point(lifeCount: 11, seconds: 60),
            point(lifeCount: 13, seconds: 180),
            point(lifeCount: 14, seconds: 240),
        ]
        let segments = GlucoseSegmenter.segments(from: points)
        #expect(segments.map(\.points.count) == [2, 2])
        #expect(GlucoseSegmenter.gaps(in: segments).map(\.duration) == [120])
    }

    @Test func segmenterBreaksWhenIntervalExceedsTwoMinutes() {
        // `life_count` consecutivo pero con 150 s de diferencia (reloj atrasado): también es hueco.
        let points = [point(lifeCount: 1, seconds: 0), point(lifeCount: 2, seconds: 150)]
        #expect(GlucoseSegmenter.segments(from: points).count == 2)
    }

    @Test func segmenterKeepsConsecutivePointsTogetherAndBreaksOnSessionChange() {
        let continuous = (0..<5).map { point(lifeCount: $0, seconds: Double($0) * 60) }
        #expect(GlucoseSegmenter.segments(from: continuous).count == 1)
        let otherSession = point(lifeCount: 5, seconds: 300, session: "other")
        #expect(GlucoseSegmenter.segments(from: continuous + [otherSession]).count == 2)
        #expect(GlucoseSegmenter.segments(from: []).isEmpty)
    }

    // MARK: Selector de período

    @Test func periodSelectorChangesTheVisibleWindow() async {
        let (model, _) = makeModel()
        var counts: [TodayPeriod: Int] = [:]
        for period in TodayPeriod.allCases {
            model.period = period
            await model.refresh()
            counts[period] = model.points.count
            #expect(model.windowEnd == Self.now)
            #expect(model.windowStart == Self.now.addingTimeInterval(-period.duration))
            #expect(model.points.allSatisfy { $0.date >= model.windowStart && $0.date <= model.windowEnd })
        }
        let six = counts[.sixHours] ?? 0
        let twelve = counts[.twelveHours] ?? 0
        let day = counts[.twentyFourHours] ?? 0
        #expect(six < twelve && twelve < day)
        // 359 minutos con lectura (lc 4140…4318 y anteriores) menos los 25 de la desconexión.
        #expect(six == 359 - PreviewData.disconnectionMinutes)
    }

    @Test func periodsExposeHoursAndAxisStride() {
        #expect(TodayPeriod.allCases.map(\.hours) == [3, 6, 12, 24])
        #expect(TodayPeriod.sixHours.duration == 21_600)
        #expect(TodayPeriod.threeHours.duration == 10_800 && TodayPeriod.threeHours.axisStrideHours == 1)
        #expect(TodayPeriod.allCases.map(\.hours) == [3, 6, 12, 24])
        #expect(TodayPeriod.twentyFourHours.axisStrideHours == 4)
    }

    // MARK: Marcas, tendencia y sensor

    @Test func marksContainOnlyMealsAndExerciseInsideTheWindow() async {
        let (model, data) = makeModel()
        model.period = .twentyFourHours
        await model.refresh()
        #expect(!model.marks.isEmpty)
        #expect(model.marks.allSatisfy { $0.date >= model.windowStart && $0.date <= model.windowEnd })
        let notes = data.events.filter { $0.kind == .note || $0.kind == .sensorNote }
        #expect(notes.isEmpty)
        #expect(Set(model.marks.map(\.kind)).isSubset(of: [.meal, .exercise]))
    }

    @Test func trendMapsJugglucoScale() {
        #expect(TrendDirection(rawTrend: 1) == .fallingFast)
        #expect(TrendDirection(rawTrend: 3) == .steady)
        #expect(TrendDirection(rawTrend: 5) == .risingFast)
        #expect(TrendDirection(rawTrend: 0) == nil)
        #expect(TrendDirection(rawTrend: nil) == nil)
        #expect(TrendDirection(rawTrend: 6) == nil)
    }

    @Test func jugglucoVectorsAreIncludedAndSynthetic() {
        let data = PreviewData(now: Self.now)
        let vectorReadings = data.readings.filter { $0.sessionID == data.vectorSession.sessionID }
        #expect(vectorReadings.count == 11)
        #expect(vectorReadings.allSatisfy { $0.synthetic })
        let warm = vectorReadings.first { $0.lifeCount == 63 }
        #expect(warm?.value == 208)
        #expect(warm?.raw.capped == 201)
        #expect(vectorReadings.filter { $0.lifeCount <= 4 }.allSatisfy { $0.value == nil })
    }

    @Test func spokenSummaryCombinesValueTrendAgeAndSensor() async {
        let (model, _) = makeModel()
        await model.refresh()
        await model.refreshSensor()
        let text = model.spokenSummary(at: Self.now)
        #expect(text.contains(String(model.latestValue ?? 0)))
        #expect(text.contains(model.sensor.state.spokenPhrase))
    }

    // MARK: Ayudas

    private func point(lifeCount: Int, seconds: Double, session: String = "s") -> GlucosePoint {
        GlucosePoint(
            id: "\(session)-\(lifeCount)",
            sessionID: session,
            lifeCount: lifeCount,
            date: Date(timeIntervalSince1970: seconds),
            value: 100
        )
    }
}
