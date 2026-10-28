import Foundation
import Synchronization
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
        model.setVisibleLength(TodayPeriod.sixHours.duration)
        await model.refresh()
        // Cargado: 6 h visibles + 6 h de búfer a la izquierda (a la derecha está ahora).
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
        model.setVisibleLength(TodayPeriod.twentyFourHours.duration)
        await model.refresh()
        let visibleGaps = model.gaps.filter { $0.start >= model.windowStart && $0.end <= model.windowEnd }
        #expect(visibleGaps.count == 2)
        let durations = visibleGaps.map(\.duration).sorted()
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
            model.setVisibleLength(period.duration)
            await model.refresh()
            counts[period] = model.visiblePoints.count
            #expect(model.period == period)
            #expect(model.windowEnd == Self.now)
            #expect(model.windowStart == Self.now.addingTimeInterval(-period.duration))
            #expect(model.visiblePoints.allSatisfy { $0.date >= model.windowStart && $0.date <= model.windowEnd })
        }
        let six = counts[.sixHours] ?? 0
        let twelve = counts[.twelveHours] ?? 0
        let day = counts[.twentyFourHours] ?? 0
        #expect(six < twelve && twelve < day)
        // 359 minutos con lectura (lc 4140…4318 y anteriores) menos los 25 de la desconexión.
        #expect(six == 359 - PreviewData.disconnectionMinutes)
    }

    @Test func periodsMatchTheVisibleLengthWithinAMinute() {
        #expect(TodayPeriod.allCases.map(\.hours) == [3, 6, 12, 24])
        #expect(TodayPeriod.sixHours.duration == 21_600)
        #expect(TodayPeriod.matching(10_800 + 59) == .threeHours)
        #expect(TodayPeriod.matching(10_800 - 60) == .threeHours)
        #expect(TodayPeriod.matching(10_800 + 61) == nil)
        #expect(TodayPeriod.matching(4.5 * 3_600) == nil)
        #expect(GlucoseChart.axisStride(for: 3_600).component == .minute)
        #expect(GlucoseChart.axisStride(for: TodayPeriod.threeHours.duration).count == 1)
        #expect(GlucoseChart.axisStride(for: TodayPeriod.twentyFourHours.duration).count == 4)
    }

    // MARK: Ventana visible, rango cargado y zoom

    @Test func loadedRangeAddsOneVisibleLengthPerSideAndStopsAtNow() async {
        let (model, _) = makeModel()
        await model.refresh()
        let length = model.visibleLength
        #expect(model.visibleEnd == Self.now && model.isLive)
        #expect(model.loadedStart == Self.now.addingTimeInterval(-2 * length))
        #expect(model.loadedEnd == Self.now, "a la derecha se acota a ahora")
        #expect(model.points.count > model.visiblePoints.count)

        // En el pasado el búfer existe por ambos lados.
        model.scrollPosition = Self.now.addingTimeInterval(-20 * 3_600)
        await model.settle()
        #expect(close(model.loadedStart, model.visibleStart.addingTimeInterval(-length)))
        #expect(close(model.loadedEnd, model.visibleEnd.addingTimeInterval(length)))
    }

    @Test func reloadsOnlyWhenTheWindowLeavesTheCentralThird() async {
        let counter = ReadCounter()
        let data = PreviewData(now: Self.now)
        let model = TodayViewModel(dataSource: CountingDataSource(base: data, counter: counter), sensorSource: data, clock: { Self.now })
        await model.refresh()
        #expect(await counter.count == 1)
        let length = model.visibleLength
        let start = model.scrollPosition

        // El centro se mueve 0,4 longitudes: sigue dentro del tercio central.
        model.scrollPosition = start.addingTimeInterval(-0.4 * length)
        #expect(!model.needsReload)
        await model.settle()
        #expect(await counter.count == 1)
        #expect(model.windowStart == model.scrollPosition, "la ventana asentada sigue al desplazamiento")

        // 0,6 longitudes: el centro sale del tercio central.
        model.scrollPosition = start.addingTimeInterval(-0.6 * length)
        #expect(model.needsReload)
        await model.settle()
        #expect(await counter.count == 2)
        #expect(!model.needsReload)
    }

    @Test func lengthChangesOverAQuarterReload() async {
        let (model, _) = makeModel()
        await model.refresh()
        let length = model.visibleLength
        model.pinch(startLength: length, magnification: 1 / 1.2, anchorDate: model.visibleEnd, anchorFraction: 1)
        #expect(!model.needsReload, "+20 %: no recarga")
        model.pinch(startLength: length, magnification: 1 / 1.3, anchorDate: model.visibleEnd, anchorFraction: 1)
        #expect(model.needsReload, "+30 %: recarga")
    }

    @Test func statsAndSpikesUseTheVisibleWindowOnly() async {
        let (model, _) = makeModel()
        model.setVisibleLength(TodayPeriod.threeHours.duration)
        await model.refresh()
        #expect(model.stats.count == model.visiblePoints.count)
        #expect(model.points.count > model.visiblePoints.count)
        #expect(model.visiblePoints.allSatisfy { $0.date >= model.windowStart && $0.date <= model.windowEnd })
        #expect(model.spikes.allSatisfy { $0.peakAt >= model.windowStart && $0.peakAt <= model.windowEnd })
        let visibleMean = Double(model.visiblePoints.map(\.value).reduce(0, +)) / Double(model.visiblePoints.count)
        #expect(abs((model.stats.mean ?? 0) - visibleMean) < 0.001)
    }

    @Test func chipAndFreeZoomAreClampedBetweenOneAndTwentyFourHours() async {
        let (model, _) = makeModel()
        await model.refresh()
        model.setVisibleLength(TodayPeriod.threeHours.duration)
        #expect(model.period == .threeHours && model.visibleEnd == Self.now)
        model.setVisibleLength(30 * 60)
        #expect(model.visibleLength == TodayViewModel.minVisibleLength)
        model.setVisibleLength(48 * 3_600)
        #expect(model.visibleLength == TodayViewModel.maxVisibleLength && model.period == .twentyFourHours)
        model.zoom(by: 2)
        #expect(model.visibleLength == TodayViewModel.maxVisibleLength)
        model.zoom(by: 0.5)
        #expect(model.period == .twelveHours)

        // Pellizco libre en el pasado: el instante bajo los dedos queda fijo.
        model.scrollPosition = Self.now.addingTimeInterval(-30 * 3_600)
        let anchor = model.visibleStart.addingTimeInterval(0.25 * model.visibleLength)
        model.pinch(startLength: 6 * 3_600, magnification: 6.0 / 4.5, anchorDate: anchor, anchorFraction: 0.25)
        #expect(abs(model.visibleLength - 4.5 * 3_600) < 0.001)
        #expect(model.period == nil, "4 h 30 min no coincide con ningún chip")
        #expect(abs(model.visibleStart.addingTimeInterval(0.25 * model.visibleLength).timeIntervalSince(anchor)) < 0.01)
        model.pinch(startLength: 6 * 3_600, magnification: 100, anchorDate: anchor, anchorFraction: 0.25)
        #expect(model.visibleLength == TodayViewModel.minVisibleLength)
        // Cerca de ahora el pellizco no deja ver el futuro.
        model.pinch(startLength: 3_600, magnification: 0.5, anchorDate: Self.now, anchorFraction: 0.5)
        #expect(model.visibleEnd <= Self.now)
    }

    @Test func pinchHapticFiresWhenCrossingExactlyOnePeriod() {
        #expect(TodayViewModel.crossesPeriod(from: 5.9 * 3_600, to: 6.1 * 3_600))
        #expect(TodayViewModel.crossesPeriod(from: 5.9 * 3_600, to: 6 * 3_600))
        #expect(!TodayViewModel.crossesPeriod(from: 6 * 3_600, to: 6.1 * 3_600), "salir de un chip no repite")
        #expect(!TodayViewModel.crossesPeriod(from: 4 * 3_600, to: 5 * 3_600))
        #expect(!TodayViewModel.crossesPeriod(from: 2 * 3_600, to: 13 * 3_600), "cruza tres: no es un cruce limpio")
    }

    @Test func liveWindowFollowsNewReadingsAndPastWindowStays() async {
        let clock = ManualTodayClock(Self.now)
        let data = PreviewData(now: Self.now)
        let model = TodayViewModel(dataSource: data, sensorSource: data, clock: { clock.now })
        await model.refresh()
        #expect(model.isLive)

        clock.advance(by: 300)
        await model.refresh()
        #expect(model.isLive && close(model.visibleEnd, clock.now), "en vivo avanza con cada carga")

        model.scrollPosition = model.scrollPosition.addingTimeInterval(-2 * 3_600)
        #expect(!model.isLive)
        let past = model.scrollPosition
        clock.advance(by: 300)
        await model.refresh()
        #expect(close(model.scrollPosition, past), "en el pasado deja de seguir")

        model.goToNow()
        #expect(model.isLive && close(model.visibleEnd, clock.now))
    }

    // MARK: Marcas, tendencia y sensor

    @Test func marksContainOnlyMealsAndExerciseInsideTheLoadedRange() async {
        let (model, data) = makeModel()
        model.setVisibleLength(TodayPeriod.twentyFourHours.duration)
        await model.refresh()
        #expect(!model.marks.isEmpty)
        #expect(model.marks.allSatisfy { $0.date >= model.loadedStart && $0.date <= model.loadedEnd })
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

/// Fuente que cuenta las consultas de lecturas (una por carga).
private actor ReadCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private struct CountingDataSource: TodayDataSource {
    let base: PreviewData
    let counter: ReadCounter

    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading] {
        await counter.increment()
        return try await base.readings(in: range)
    }

    func latestEligibleReading() async throws -> GlucoseReading? { try await base.latestEligibleReading() }

    func diaryEvents(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent] { try await base.diaryEvents(in: range) }

    func changes() -> AsyncStream<Void> { base.changes() }
}

/// Reloj que avanza a mano.
private final class ManualTodayClock: Sendable {
    private let value: Mutex<Date>

    init(_ start: Date) { value = Mutex(start) }

    var now: Date { value.withLock { $0 } }

    func advance(by seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

/// Fechas iguales salvo redondeo de coma flotante.
private func close(_ lhs: Date, _ rhs: Date) -> Bool {
    abs(lhs.timeIntervalSince(rhs)) < 0.001
}
