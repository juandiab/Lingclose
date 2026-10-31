import Foundation
import LingoCore

/// `SleepActivityReading` sintético para pruebas y previsualizaciones (T-33): noches y pasos inventados para cada día
/// del rango, o listas fijas si se dan. Nunca toca Apple Salud.
struct PreviewSleepActivityReader: SleepActivityReading {
    var fixedNights: [SleepNight]?
    var fixedSteps: [DailySteps]?

    init(nights: [SleepNight]? = nil, steps: [DailySteps]? = nil) {
        fixedNights = nights
        fixedSteps = steps
    }

    func requestAuthorization() async {}

    func sleepNights(from: Date, to: Date, timeZone: TimeZone) async -> [SleepNight] {
        if let fixedNights { return fixedNights }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var segments: [SleepSegment] = []
        for (index, day) in Self.days(from: from, to: to, calendar: calendar).enumerated() {
            // Acostarse entre 22:40 y 00:10; dormir de 6 h 20 a 7 h 50, con un despertar a mitad de la noche.
            let bed = day.addingTimeInterval(TimeInterval(22 * 3_600 + 40 * 60 + (index * 37 % 90) * 60))
            let asleep = TimeInterval(380 + (index * 53 % 90)) * 60
            let half = bed.addingTimeInterval(10 * 60 + asleep / 2)
            let wake = bed.addingTimeInterval(10 * 60 + asleep + 8 * 60)
            guard wake <= to else { continue }
            segments += [
                SleepSegment(start: bed, end: bed.addingTimeInterval(10 * 60), stage: .awake, source: "preview.watch"),
                SleepSegment(start: bed.addingTimeInterval(10 * 60), end: half.addingTimeInterval(-60 * 60), stage: .core, source: "preview.watch"),
                SleepSegment(start: half.addingTimeInterval(-60 * 60), end: half, stage: .deep, source: "preview.watch"),
                SleepSegment(start: half, end: half.addingTimeInterval(8 * 60), stage: .awake, source: "preview.watch"),
                SleepSegment(start: half.addingTimeInterval(8 * 60), end: wake.addingTimeInterval(-90 * 60), stage: .core, source: "preview.watch"),
                SleepSegment(start: wake.addingTimeInterval(-90 * 60), end: wake, stage: .rem, source: "preview.watch"),
            ]
        }
        return SleepNightGrouper.nights(from: segments, timeZone: timeZone)
    }

    func dailySteps(from: Date, to: Date, timeZone: TimeZone) async -> [DailySteps] {
        if let fixedSteps { return fixedSteps }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let intervals = Self.days(from: from, to: to, calendar: calendar).enumerated().map { index, day in
            (start: day, steps: Double(4_200 + (index * 2_731) % 7_500))
        }
        return DailySteps.days(from: intervals, timeZone: timeZone)
    }

    /// Medianoches locales de los días que tocan `[from, to)`.
    private static func days(from: Date, to: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: from)
        while day < to {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}
