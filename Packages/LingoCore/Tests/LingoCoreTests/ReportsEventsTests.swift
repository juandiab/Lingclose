import Foundation
import Testing
@testable import LingoCore

/// Comidas, ejercicio, noches y franjas del motor de reportes (T-27a).
struct ReportsEventsTests {
    private typealias F = ReportsFixture

    @Test func mealResponsesAndGroups() throws {
        let period = F.days("2026-10-01", "2026-10-07")
        let mealTimes = [F.local("2026-10-01", 8), F.local("2026-10-02", 8), F.local("2026-10-03", 8), F.local("2026-10-04", 13)]
        let samples = F.series(period) { t in F.minutesSinceLast(mealTimes, t).map(F.mealCurve) ?? 100 }
        let events = [
            F.event(.meal, at: mealTimes[0], carbs: 50, text: "Plato secreto", id: "meal-secret-id"),
            F.event(.meal, at: mealTimes[1], carbs: 60), F.event(.meal, at: mealTimes[2], carbs: 45),
            F.event(.meal, at: mealTimes[3]),
            F.event(.meal, at: F.local("2026-10-05", 8), carbs: 30).with(deleted: true),
        ]
        let report = ReportBuilder.build(samples: samples, events: events, period: period).meals
        #expect(report.meals.count == 4)
        for meal in report.meals {
            let r = try #require(meal.response)
            #expect(r.baseline == 100 && r.peak == 160 && r.rise == 60 && r.timeToPeakMinutes == 45)
            #expect(r.returnMinutes == 110 && r.score == 59 && r.timeAboveRangeMinutes == 0)
            #expect(!meal.overlapsPreviousMeal)
        }
        #expect(report.meals.map(\.slot) == [.morning, .morning, .morning, .midday])
        #expect(report.meals.map(\.localMinute) == [480, 480, 480, 780])
        #expect(report.overall.analyzed == 4 && report.overall.meanRise == 60 && report.overall.meanScore == 59)
        #expect(report.overall.returnedFraction == 1 && report.overall.meanTimeToPeakMinutes == 45)

        let morning = try #require(report.bySlot.first { $0.key == .morning }).stats
        #expect(morning.isReliable && morning.meanRise == 60 && morning.medianRise == 60 && morning.meanPeak == 160)
        let midday = try #require(report.bySlot.first { $0.key == .midday }).stats
        #expect(midday.meals == 1 && !midday.isReliable && midday.meanRise == nil)
        #expect(report.byCarbs.map(\.key) == CarbBucket.allCases)
        #expect(report.byCarbs.first { $0.key == .from45To75 }?.stats.analyzed == 3)
        #expect(report.byCarbs.first { $0.key == .unknown }?.stats.analyzed == 1)
    }

    @Test func mealWithoutFollowUpHasNoResponseAndOverlapIsMarked() throws {
        let period = F.days("2026-10-01", "2026-10-01")
        let samples = F.series(period) { _ in 100 }.filter { $0.measuredAt < F.local("2026-10-01", 20) }
        let events = [F.event(.meal, at: F.local("2026-10-01", 12)), F.event(.meal, at: F.local("2026-10-01", 14)),
                      F.event(.meal, at: F.local("2026-10-01", 19, 30))]
        let meals = ReportBuilder.build(samples: samples, events: events, period: period).meals.meals
        #expect(meals.map(\.overlapsPreviousMeal) == [false, true, false])
        #expect(meals[0].response != nil && meals[2].response == nil)
    }

    @Test func exerciseEffectsAndDurationGroups() throws {
        let period = F.days("2026-10-01", "2026-10-07")
        let starts = (1...4).map { F.local("2026-10-0\($0)", 17) }
        let samples = F.series(period) { t in
            switch F.minutesSinceLast(starts, t) {
            case .some(let m) where m <= 30: 120 - m
            case .some(let m) where m <= 150: 90
            default: 120
            }
        }
        let events = starts.prefix(3).map { F.event(.exercise, at: $0, duration: 30, text: "Ruta secreta") }
            + [F.event(.exercise, at: starts[3])]
        let report = ReportBuilder.build(samples: samples, events: events, period: period).exercise
        #expect(report.sessions.count == 4)
        for session in report.sessions {
            let e = try #require(session.effect)
            #expect(e.baseline == 120 && e.minimum == 90 && e.minutesToMinimum == 30 && e.dropToMinimum == -30)
            #expect(e.deltaAtEnd == -30 && e.deltaAt60 == -30 && e.deltaAt120 == -30)
        }
        #expect(report.sessions.map(\.durationBucket) == [.from30To60, .from30To60, .from30To60, .unspecified])
        #expect(report.sessions.map(\.slot) == [.evening, .evening, .evening, .evening])
        let medium = try #require(report.byDuration.first { $0.key == .from30To60 }).stats
        #expect(medium.isReliable && medium.meanDeltaAtEnd == -30 && medium.meanDeltaAt120 == -30 && medium.meanDropToMinimum == -30)
        #expect(report.byDuration.first { $0.key == .unspecified }?.stats.meanDeltaAtEnd == nil)
        #expect(report.overall.analyzed == 4 && report.overall.meanDeltaAt60 == -30)
    }

    @Test func nightsFindLowEpisodes() throws {
        let period = F.days("2026-10-01", "2026-10-07")
        let samples = F.series(period) { t in
            let localMinute = Int(((t.epochSeconds - 5 * 3600) % 86_400) / 60)
            return (180..<200).contains(localMinute) ? 60 : 100   // 03:00–03:19 bajo
        }
        let report = ReportBuilder.build(samples: samples, events: [], period: period).nights
        let reliable = report.nights.filter(\.isReliable)
        #expect(reliable.count == 7 && reliable.allSatisfy { $0.lowEpisodes == 1 })
        let night = try #require(report.nights.first { $0.night == "2026-10-02" })
        #expect(night.start == F.local("2026-10-02", 23) && night.end == F.local("2026-10-03", 7))
        #expect(night.minimumAt == F.local("2026-10-03", 3) && night.stats.minimum == 60 && night.median == 100)
        #expect(night.stats.coverage == 1)
        #expect(report.summary.isReliable && report.summary.nightsWithLowEpisode == 7 && report.summary.meanMinimum == 60)

        // Un bajón de solo 10 min no es episodio.
        let short = F.series(period) { t in
            let localMinute = Int(((t.epochSeconds - 5 * 3600) % 86_400) / 60)
            return (180..<190).contains(localMinute) ? 60 : 100
        }
        let none = ReportBuilder.build(samples: short, events: [], period: period).nights
        #expect(none.nights.allSatisfy { $0.lowEpisodes == 0 })
    }

    @Test func customNightWindowWithoutMidnightCrossing() {
        let period = F.days("2026-10-01", "2026-10-03")
        let config = ReportConfiguration(nightStartMinute: 60, nightEndMinute: 300)
        let report = ReportBuilder.build(samples: F.series(period) { _ in 100 }, events: [], period: period, configuration: config).nights
        #expect(report.nights.map(\.night) == ["2026-10-01", "2026-10-02", "2026-10-03"])
        #expect(report.nights.allSatisfy { $0.end.epochSeconds - $0.start.epochSeconds == 4 * 3600 && $0.isReliable })
    }

    @Test func timeOfDayPatternsCountFastRises() throws {
        let period = F.days("2026-10-01", "2026-10-07")
        let samples = F.series(period) { t in
            let m = Int(((t.epochSeconds - 5 * 3600) % 86_400) / 60) - 13 * 60   // minutos desde las 13:00
            switch m {
            case 0...30: return 100 + 3 * m
            case 31...120: return 190
            case 121...210: return 190 - (m - 120)
            default: return 100
            }
        }
        let slots = ReportBuilder.build(samples: samples, events: [], period: period).timeOfDay.slots
        let midday = try #require(slots.first { $0.slot == .midday })
        #expect(midday.fastRises == 7 && midday.fastFalls == 0 && midday.fastRisesPerDay == 1 && midday.isReliable)
        #expect(slots.filter { $0.slot != .midday }.allSatisfy { $0.fastRises == 0 && $0.fastFalls == 0 })
        let morning = try #require(slots.first { $0.slot == .morning })
        #expect(morning.stats.mean == 100 && morning.stats.timeInRange == 1 && morning.stats.coverage == 1)
        #expect(try #require(midday.stats.timeHigh) > 0)
    }
}

extension ReportsEventsTests {
    /// El cálculo por días con margen da lo mismo que `RateOfChange.events` de una pasada, también con episodios
    /// que cruzan la medianoche.
    @Test func chunkedRateEventsMatchSinglePass() {
        let period = F.days("2026-10-01", "2026-10-04")
        let samples = F.series(period) { t in
            let m = Int(((t.epochSeconds - 5 * 3600) % 86_400) / 60)
            let wave = 110 + Int(35 * sin(Double(t.epochSeconds / 60) / 47))
            switch m {
            case 1420...: return 100 + 3 * (m - 1420)          // 23:40 → sube hasta medianoche…
            case 0..<20: return 160 + 3 * m                    // …y sigue subiendo tras ella
            case 20..<90: return 220 - 2 * (m - 20)            // luego baja
            default: return wave
            }
        }
        let context = ReportContext(samples: samples, events: [], period: period, configuration: .default)
        let single = RateOfChange.events(in: samples)
        #expect(!single.isEmpty)
        #expect(context.rateEvents == single)
    }
}

private extension DiaryEvent {
    func with(deleted: Bool) -> DiaryEvent {
        var copy = self
        copy.deleted = deleted
        return copy
    }
}
