import Foundation
import Testing
@testable import LingoCore

/// Motor de reportes (T-27a): resumen, perfil horario, días, semanas y casos borde.
struct ReportsBuilderTests {
    private typealias F = ReportsFixture

    @Test func noDataGivesEmptyButValidReports() throws {
        let period = F.days("2026-10-01", "2026-10-07")
        let bundle = ReportBuilder.build(samples: [], events: [], period: period)
        #expect(!bundle.hasData)
        #expect(bundle.dayCount == 7)
        #expect(bundle.summary.stats.readings == 0 && bundle.summary.stats.mean == nil && bundle.summary.stats.coverage == 0)
        #expect(bundle.summary.gaps == 1 && bundle.summary.gapMinutes == 7 * 1440)
        #expect(!bundle.summary.hasEnoughData)
        #expect(bundle.hourlyProfile.bins.count == 48 && bundle.hourlyProfile.reportedBins == 0)
        #expect(bundle.dailyOverlay.days.allSatisfy { $0.values.allSatisfy { $0 == nil } })
        #expect(bundle.weeklyComparison.deltas == nil)
        #expect(bundle.meals.meals.isEmpty && bundle.exercise.sessions.isEmpty)
        #expect(!bundle.nights.hasEnoughData && bundle.nights.summary.medianOfMedians == nil)
        #expect(!bundle.timeOfDay.hasEnoughData)
        #expect(bundle.series.values.count == 7 * 288 && bundle.series.values.allSatisfy { $0 == nil })
        _ = try bundle.snapshot.jsonData()
    }

    @Test func zeroLengthPeriodHasNoDays() {
        let t = F.instant("2026-10-01T12:00:00Z")
        let bundle = ReportBuilder.build(samples: [], events: [], period: ReportPeriod(start: t, end: t, timeZone: F.bogota))
        #expect(bundle.dayCount == 0 && bundle.weeklyComparison.current == nil && bundle.nights.nights.isEmpty)
    }

    @Test func constantWeekFillsEveryReport() throws {
        let period = F.days("2026-10-01", "2026-10-07")
        #expect(period.start == F.instant("2026-10-01T05:00:00Z") && period.end == F.instant("2026-10-08T05:00:00Z"))
        let bundle = ReportBuilder.build(samples: F.series(period) { _ in 100 }, events: [], period: period)

        let stats = bundle.summary.stats
        #expect(stats.readings == 7 * 1440 && stats.coveredMinutes == 7 * 1440 && stats.coverage == 1)
        #expect(stats.mean == 100 && stats.standardDeviation == 0 && stats.coefficientOfVariation == 0)
        #expect(stats.timeInRange == 1 && stats.timeLow == 0 && stats.timeHigh == 0 && stats.timeVeryHigh == 0)
        #expect(bundle.summary.gaps == 0 && bundle.summary.gapMinutes == 0 && bundle.summary.daysWithData == 7)
        #expect(bundle.summary.days.map(\.day.date) == (1...7).map { "2026-10-0\($0)" })
        #expect(bundle.summary.days[0].day.weekday == 4, "2026-10-01 es jueves")

        #expect(bundle.hourlyProfile.reportedBins == 48)
        for (k, bin) in bundle.hourlyProfile.bins.enumerated() {
            #expect(bin.startMinute == 30 * k && bin.readings == 7 * 30 && bin.days == 7)
            #expect(bin.p5 == 100 && bin.p50 == 100 && bin.p95 == 100)
        }
        #expect(bundle.dailyOverlay.days.count == 7)
        #expect(bundle.dailyOverlay.days.allSatisfy { $0.values.count == 288 && $0.values.allSatisfy { $0 == 100 } })

        // Semana actual completa; la anterior sin datos → sin deltas.
        let current = try #require(bundle.weeklyComparison.current)
        #expect(current.firstDay == "2026-10-01" && current.lastDay == "2026-10-07" && current.daysWithData == 7)
        #expect(bundle.weeklyComparison.previous?.daysWithData == 0 && bundle.weeklyComparison.deltas == nil)

        // Noches: la del 30-sep (recortada a 7 de 8 h, fiable), 1…6-oct completas y la del 7 (1 de 8 h, no fiable).
        #expect(bundle.nights.nights.map(\.night) == ["2026-09-30"] + (1...7).map { "2026-10-0\($0)" })
        #expect(bundle.nights.nights.map(\.isReliable) == [true, true, true, true, true, true, true, false])
        #expect(bundle.nights.summary.reliableNights == 7 && bundle.nights.summary.medianOfMedians == 100)
        #expect(bundle.nights.summary.nightsWithLowEpisode == 0)

        #expect(bundle.timeOfDay.slots.map(\.slot) == TimeOfDaySlot.allCases)
        #expect(bundle.timeOfDay.slots.allSatisfy { $0.isReliable && $0.days == 7 && $0.stats.mean == 100 && $0.fastRises == 0 })
        #expect(bundle.series.intervalMinutes == 5 && bundle.series.values.count == 7 * 288)
    }

    @Test func bandsFollowConfiguration() {
        let period = F.days("2026-10-01", "2026-10-01")
        let cycle = [60, 100, 200, 300]
        let samples = F.series(period) { cycle[Int(($0.epochSeconds / 60) % 4)] }
        let stats = ReportBuilder.build(samples: samples, events: [], period: period).summary.stats
        #expect(stats.timeLow == 0.25 && stats.timeInRange == 0.25 && stats.timeHigh == 0.25 && stats.timeVeryHigh == 0.25)
        #expect(stats.minimum == 60 && stats.maximum == 300 && stats.mean == 165)

        let custom = ReportConfiguration(range: 80...160, veryHighThreshold: 220)
        let other = ReportBuilder.build(samples: samples, events: [], period: period, configuration: custom).summary.stats
        #expect(other.timeLow == 0.25 && other.timeInRange == 0.25 && other.timeHigh == 0.25 && other.timeVeryHigh == 0.25)
        #expect(GlucoseBand(valueMgdl: 70, configuration: custom) == .low)
        #expect(GlucoseBand(valueMgdl: 160, configuration: custom) == .inRange)
        #expect(GlucoseBand(valueMgdl: 220, configuration: custom) == .high)
        #expect(GlucoseBand(valueMgdl: 221, configuration: custom) == .veryHigh)
        #expect(ReportConfiguration(range: 70...180, veryHighThreshold: 150).veryHighThreshold == 180)
    }

    @Test func gapsAreCountedWithTheirFullLength() {
        let period = F.days("2026-10-01", "2026-10-01")
        let holeStart = period.start.adding(seconds: 600 * 60), holeEnd = period.start.adding(seconds: 720 * 60)
        let samples = F.series(period) { _ in 120 }.filter { !($0.measuredAt >= holeStart && $0.measuredAt < holeEnd) }
            .filter { $0.measuredAt < period.end.adding(seconds: -30 * 60) }
        let summary = ReportBuilder.build(samples: samples, events: [], period: period).summary
        // Hueco interno de 599 → 720 (121 min) y final de 1409 → 1440 (31 min). Los de 1 min no cuentan.
        #expect(summary.gaps == 2 && summary.gapMinutes == 152 && summary.longestGapMinutes == 121)
        #expect(summary.stats.readings == 1440 - 120 - 30)
    }

    @Test func singleDayIsBelowEveryMultiDayMinimum() throws {
        let period = F.days("2026-10-01", "2026-10-01")
        let bundle = ReportBuilder.build(samples: F.series(period) { _ in 100 }, events: [], period: period)
        #expect(bundle.summary.hasEnoughData && bundle.summary.daysWithData == 1)
        #expect(bundle.hourlyProfile.reportedBins == 0 && bundle.hourlyProfile.bins.allSatisfy { $0.days == 1 && $0.p50 == nil })
        #expect(bundle.timeOfDay.slots.allSatisfy { !$0.isReliable && $0.fastRisesPerDay == nil })
        #expect(try #require(bundle.weeklyComparison.current).isReliable == false)
        #expect(bundle.weeklyComparison.deltas == nil)
        #expect(!bundle.nights.hasEnoughData)
    }

    @Test func presetEndsAtNowAndCountsTheCurrentDay() {
        let now = F.local("2026-10-07", 12)
        let period = ReportPeriod.preset(.days7, endingAt: now, timeZone: F.bogota)
        #expect(period.start == F.local("2026-10-01", 0) && period.end == now)
        let bundle = ReportBuilder.build(samples: F.series(period) { _ in 100 }, events: [], period: period)
        #expect(bundle.dayCount == 7 && bundle.summary.stats.coverage == 1)
        #expect(bundle.summary.days.last?.stats.coverage == 1, "la cobertura de hoy se mide sobre la parte transcurrida")
        #expect(period.dataStart == F.local("2026-09-24", 0).adding(seconds: -1800))
    }

    @Test func daylightSavingDayHas25HoursAndKeepsWallClock() throws {
        let tz = F.newYork
        let period = F.days("2026-10-30", "2026-11-01", tz)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let samples = F.series(period) { 100 + calendar.component(.hour, from: $0.date) }
        let bundle = ReportBuilder.build(samples: samples, events: [], period: period)

        let days = bundle.summary.days
        #expect(days.map(\.day.date) == ["2026-10-30", "2026-10-31", "2026-11-01"])
        #expect(days.map(\.day.weekday) == [5, 6, 7])
        #expect(days.map(\.day.durationSeconds) == [86_400, 86_400, 90_000])
        #expect(days[2].stats.readings == 1500 && days[2].stats.coverage == 1)
        #expect(bundle.summary.gaps == 0)

        // Cada bin de 30 min tiene el valor de su hora local; el de 01:00 suma la hora repetida.
        for (k, bin) in bundle.hourlyProfile.bins.enumerated() {
            #expect(bin.p50 == Double(100 + k / 2) && bin.p5 == bin.p95)
            #expect(bin.readings == ((k / 2) == 1 ? 120 : 90))
        }
        let sunday = try #require(bundle.dailyOverlay.days.last)
        #expect(sunday.values[12] == 101 && sunday.values[0] == 100 && sunday.values[287] == 123)
        #expect(bundle.series.values.count == (3 * 1440 + 60) / 5)
    }

    @Test func sameSamplesInAnotherZoneMoveTheLocalHours() {
        let bogota = F.days("2026-10-01", "2026-10-03")
        let samples = F.series(bogota) { t in
            // 200 entre las 12:00 y las 12:59 de Bogotá; 100 el resto.
            ((t.epochSeconds - 5 * 3600) % 86_400) / 3600 == 12 ? 200 : 100
        }
        let here = ReportBuilder.build(samples: samples, events: [], period: bogota).hourlyProfile.bins
        let utc = ReportPeriod(start: bogota.start, end: bogota.end, timeZone: TimeZone(identifier: "UTC")!)
        let there = ReportBuilder.build(samples: samples, events: [], period: utc).hourlyProfile.bins
        #expect(here[24].p50 == 200 && here[34].p50 == 100)
        #expect(there[34].p50 == 200 && there[24].p50 == 100)
    }

    @Test func weeklyComparisonUsesDataBeforeThePeriod() throws {
        let period = F.days("2026-10-08", "2026-10-14")
        let all = F.days("2026-10-01", "2026-10-14")
        #expect(period.dataStart <= all.start)
        let split = period.start
        let samples = F.series(all) { $0 < split ? 100 : 200 }
        let events = [
            F.event(.meal, at: F.local("2026-10-02", 8)), F.event(.meal, at: F.local("2026-10-03", 8)),
            F.event(.meal, at: F.local("2026-10-09", 8)), F.event(.meal, at: F.local("2026-10-10", 8)),
            F.event(.meal, at: F.local("2026-10-11", 8)),
            F.event(.exercise, at: F.local("2026-10-04", 17)),
            F.event(.exercise, at: F.local("2026-10-12", 17), duration: 45),
            F.event(.note, at: F.local("2026-10-12", 9), text: "nota"),
        ]
        let weekly = ReportBuilder.build(samples: samples, events: events, period: period).weeklyComparison
        let current = try #require(weekly.current), previous = try #require(weekly.previous)
        #expect(current.firstDay == "2026-10-08" && previous.firstDay == "2026-10-01" && previous.lastDay == "2026-10-07")
        #expect(current.stats.mean == 200 && previous.stats.mean == 100)
        #expect(current.meals == 3 && previous.meals == 2)
        #expect(current.exerciseMinutes == 45 && previous.exerciseMinutes == 30)
        let deltas = try #require(weekly.deltas)
        #expect(deltas.mean == 100 && deltas.timeInRange == -1 && deltas.standardDeviation == 0)
        #expect(deltas.meals == 1 && deltas.exerciseMinutes == 15)
    }

    @Test func weekWithFewDaysIsNotCompared() {
        let period = F.days("2026-10-01", "2026-10-14")
        // Semana anterior con solo 3 días de datos.
        let samples = F.series(period) { _ in 100 }.filter { $0.measuredAt >= F.local("2026-10-05", 0) }
        let weekly = ReportBuilder.build(samples: samples, events: [], period: period).weeklyComparison
        #expect(weekly.previous?.daysWithData == 3 && weekly.previous?.isReliable == false)
        #expect(weekly.deltas == nil)
    }

    @Test func buildFromReadingsKeepsOnlyEligibleGlucose() {
        let session = TestSupport.session(warmup: 60)
        var readings = (0..<200).map { lc in
            TestSupport.reading(session, lc: lc, raw: TestSupport.raw(uncapped: 100, capped: 100), origin: .live)
        }
        readings[150].deleted = true
        readings.append(TestSupport.reading(session, lc: 200, raw: TestSupport.raw(uncapped: 100, capped: 100, qualityFlag: true),
                                            origin: .live))
        let start = UTCInstant(epochSeconds: TestSupport.activationEpoch)
        let period = ReportPeriod(start: start, end: start.adding(seconds: 86_400), timeZone: F.bogota)
        let bundle = ReportBuilder.build(readings: readings, events: [], period: period)
        let eligible = readings.filter { !$0.deleted && $0.eligibility.isEligible && $0.value != nil }.count
        #expect(eligible == 139)
        #expect(bundle.summary.stats.readings == eligible)
    }

    @Test func outputIsDeterministicRegardlessOfInputOrder() throws {
        let period = F.days("2026-10-01", "2026-10-03")
        let samples = F.series(period) { 80 + Int(($0.epochSeconds / 60) % 97) }
        let events = [F.event(.meal, at: F.local("2026-10-02", 8), carbs: 40, id: "b"),
                      F.event(.meal, at: F.local("2026-10-02", 8), carbs: 10, id: "a"),
                      F.event(.exercise, at: F.local("2026-10-03", 18), duration: 20)]
        let a = ReportBuilder.build(samples: samples, events: events, period: period)
        let b = ReportBuilder.build(samples: samples.reversed() + samples.prefix(500), events: events.reversed(), period: period)
        #expect(a == b)
        #expect(try a.snapshot.jsonData() == b.snapshot.jsonData())
        #expect(a.meals.meals.map(\.carbsG) == [10, 40], "empate de hora: orden por event_id")
    }
}
