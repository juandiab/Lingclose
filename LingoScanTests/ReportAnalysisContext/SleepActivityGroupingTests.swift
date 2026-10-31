import Foundation
import LingoCore
import Testing
@testable import LingoScan

/// Agrupado de sueño por noche y de pasos por día (T-33), con tramos sintéticos: sin HealthKit.
struct SleepActivityGroupingTests {
    private let zone = TimeZone(identifier: "America/Bogota")!

    /// Fecha local en Bogotá (UTC−5) → `Date`.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func segment(_ start: Date, _ end: Date, _ stage: SleepStage, _ source: String = "watch") -> SleepSegment {
        SleepSegment(start: start, end: end, stage: stage, source: source)
    }

    @Test func nightBelongsToTheDayItStartsLikeNightReport() {
        // Empieza el 20 a las 23:00 → noche del 20. Empieza el 22 a las 00:30 → noche del 21 (antes de las 12:00).
        let nights = SleepNightGrouper.nights(from: [
            segment(at(20, 23), at(21, 6, 30), .asleepUnspecified, "phone"),
            segment(at(22, 0, 30), at(22, 7), .asleepUnspecified, "phone"),
        ], timeZone: zone)
        #expect(nights.map(\.night) == ["2026-10-20", "2026-10-21"])
        #expect(nights[0].asleepMin == 450)
        #expect(nights[0].deepMin == nil && nights[0].remMin == nil && nights[0].coreMin == nil)
        #expect(nights[0].bedAt == UTCInstant(at(20, 23)) && nights[0].wakeAt == UTCInstant(at(21, 6, 30)))
    }

    @Test func stagesAwakeningsAndInBed() {
        let nights = SleepNightGrouper.nights(from: [
            segment(at(20, 22, 30), at(21, 6, 40), .inBed),
            segment(at(20, 22, 50), at(21, 1), .core),
            segment(at(21, 1), at(21, 2), .deep),
            segment(at(21, 2), at(21, 2, 10), .awake),
            segment(at(21, 2, 10), at(21, 5), .core),
            segment(at(21, 5), at(21, 5, 5), .awake),
            segment(at(21, 5, 5), at(21, 6, 20), .rem),
            segment(at(21, 6, 20), at(21, 6, 40), .awake), // al final: no es un despertar entre sueños
        ], timeZone: zone)
        #expect(nights.count == 1)
        let night = nights[0]
        #expect(night.night == "2026-10-20")
        #expect(night.inBedMin == 490)
        #expect(night.asleepMin == 130 + 60 + 170 + 75)
        #expect(night.awakeMin == 10 + 5 + 20)
        #expect(night.deepMin == 60 && night.remMin == 75 && night.coreMin == 300)
        #expect(night.awakenings == 2)
    }

    @Test func prefersTheSourceWithStagesAndNeverCountsTwice() {
        let nights = SleepNightGrouper.nights(from: [
            segment(at(20, 22), at(21, 7), .asleepUnspecified, "phone"),
            segment(at(20, 23), at(21, 3), .core, "watch"),
            segment(at(21, 3), at(21, 4), .deep, "watch"),
            segment(at(21, 4), at(21, 6), .rem, "watch"),
        ], timeZone: zone)
        #expect(nights.count == 1)
        #expect(nights[0].asleepMin == 420)
        #expect(nights[0].deepMin == 60)
        #expect(nights[0].bedAt == UTCInstant(at(20, 23)))
    }

    @Test func aNapDoesNotJoinTheNight() {
        let nights = SleepNightGrouper.nights(from: [
            segment(at(20, 14), at(20, 14, 40), .asleepUnspecified),
            segment(at(20, 23), at(21, 6), .asleepUnspecified),
        ], timeZone: zone)
        #expect(nights.count == 1)
        #expect(nights[0].asleepMin == 420)
        #expect(nights[0].bedAt == UTCInstant(at(20, 23)))
    }

    @Test func stepsAreSummedPerLocalDay() {
        let days = DailySteps.days(from: [
            (at(20, 0), 4_000), (at(20, 23, 30), 500), (at(21, 0), 7_250.4), (at(22, 0), 0), (at(23, 0), .nan),
        ], timeZone: zone)
        #expect(days == [DailySteps(day: "2026-10-20", steps: 4_500), DailySteps(day: "2026-10-21", steps: 7_250)])
    }

    @Test func previewReaderInventsOneNightPerDay() async {
        let reader = PreviewSleepActivityReader()
        let nights = await reader.sleepNights(from: at(10, 12), to: at(17, 12), timeZone: zone)
        #expect(nights.count == 7)
        #expect(nights.allSatisfy { $0.asleepMin > 300 && $0.awakenings == 1 && $0.deepMin != nil })
        let steps = await reader.dailySteps(from: at(10, 0), to: at(17, 0), timeZone: zone)
        #expect(steps.count == 7)
    }
}
