import Foundation
import LingoCore
import Testing
@testable import LingoScan

@MainActor
struct ReportsViewModelTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated static let bogota = TimeZone(identifier: "America/Bogota")!

    private func makeModel(
        source: any ReportsDataSource = PreviewReportsDataSource(data: PreviewData(now: ReportsViewModelTests.now)),
        clock: TestClock = TestClock(start: ReportsViewModelTests.now)
    ) -> (ReportsViewModel, UserDefaults) {
        let suite = "reports-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = ReportsViewModel(
            dataSource: source, clock: { clock.now }, timeZone: Self.bogota, defaults: defaults)
        return (model, defaults)
    }

    @Test func loadsFourteenSyntheticDaysByDefault() async throws {
        let (model, _) = makeModel()
        #expect(model.preset == .days14)
        await model.appear()
        let content = try #require(model.content)
        #expect(content.preset == .days14)
        #expect(content.bundle.dayCount == 14)
        #expect(content.hasData)
        #expect(content.bundle.summary.daysWithData >= 13)
        #expect(content.bundle.meals.hasEnoughData)
        #expect(content.bundle.exercise.hasEnoughData)
        #expect(content.bundle.weeklyComparison.hasEnoughData)
        #expect(content.bundle.nights.hasEnoughData)
        #expect(content.bundle.summary.gaps > 0)
        #expect(model.isSynthetic)
        #expect(!model.isLoading)
    }

    @Test func usesTheStoredReferenceRange() async throws {
        let (model, _) = makeModel()
        #expect(model.configuration.range == ReferenceLines.defaultLow...ReferenceLines.defaultHigh)
        await model.appear()
        await model.updateReference(low: 80, high: 160)
        let content = try #require(model.content)
        #expect(content.configuration.range == 80...160)
    }

    @Test func cachesForAMinuteThenRecomputes() async throws {
        let clock = TestClock(start: Self.now)
        let source = ReportsCountingSource(base: PreviewReportsDataSource(data: PreviewData(now: Self.now)))
        let (model, _) = makeModel(source: source, clock: clock)
        await model.appear()
        #expect(source.readingCalls == 1)
        await model.appear()
        await model.sceneDidBecomeActive()
        #expect(source.readingCalls == 1)
        clock.advance(by: .seconds(ReportsViewModel.refreshInterval + 1))
        await model.sceneDidBecomeActive()
        #expect(source.readingCalls == 2)
    }

    @Test func cachesEachPeriodSeparately() async throws {
        let source = ReportsCountingSource(base: PreviewReportsDataSource(data: PreviewData(now: Self.now)))
        let (model, defaults) = makeModel(source: source)
        await model.appear()
        await model.select(.days7)
        #expect(model.content?.preset == .days7)
        #expect(model.content?.bundle.dayCount == 7)
        #expect(defaults.integer(forKey: ReportsViewModel.presetKey) == 7)
        await model.select(.days14)
        #expect(model.content?.preset == .days14)
        #expect(source.readingCalls == 2)
    }

    @Test func remembersThePeriod() async throws {
        let (first, defaults) = makeModel()
        await first.select(.days30)
        let second = ReportsViewModel(dataSource: EmptyReportsDataSource(), defaults: defaults)
        #expect(second.preset == .days30)
    }

    @Test func referenceChangeInvalidatesTheCache() async throws {
        let source = ReportsCountingSource(base: PreviewReportsDataSource(data: PreviewData(now: Self.now)))
        let (model, _) = makeModel(source: source)
        await model.appear()
        await model.updateReference(low: 70, high: 180)
        #expect(source.readingCalls == 2)
        #expect(model.content?.configuration.range == 70...180)
        await model.updateReference(low: 70, high: 180)
        #expect(source.readingCalls == 2)
    }

    @Test func failureIsReportedAndRetried() async throws {
        let source = ReportsCountingSource(base: PreviewReportsDataSource(data: PreviewData(now: Self.now)))
        source.setFailing(true)
        let (model, _) = makeModel(source: source)
        await model.appear()
        #expect(model.failure == .unavailable)
        #expect(model.content == nil)
        source.setFailing(false)
        await model.retry()
        #expect(model.failure == nil)
        #expect(model.content != nil)
    }

    @Test func emptySourceGivesEmptyReports() async throws {
        let (model, _) = makeModel(source: EmptyReportsDataSource())
        await model.appear()
        let content = try #require(model.content)
        #expect(!content.hasData)
        for route in ReportRoute.allCases {
            #expect(!route.hasDetail(content), "\(route) no debería abrir detalle sin datos")
        }
        #expect(content.profile.isEmpty)
        #expect(content.overlayCompact.isEmpty)
    }
}
