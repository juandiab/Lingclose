import Foundation

/// Pasos de un día local (`YYYY-MM-DD`) de Apple Salud (T-33).
struct DailySteps: Sendable, Hashable, Codable {
    var day: String
    var steps: Int

    /// Suma de pasos por intervalo diario → un `DailySteps` por día con pasos (> 0), ordenados por fecha.
    static func days(from intervals: [(start: Date, steps: Double)], timeZone: TimeZone) -> [DailySteps] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var totals: [String: Double] = [:]
        for interval in intervals where interval.steps.isFinite && interval.steps > 0 {
            totals[SleepNightGrouper.dayString(interval.start, calendar: calendar), default: 0] += interval.steps
        }
        return totals.map { DailySteps(day: $0.key, steps: Int($0.value.rounded())) }
            .filter { $0.steps > 0 }
            .sorted { $0.day < $1.day }
    }
}
