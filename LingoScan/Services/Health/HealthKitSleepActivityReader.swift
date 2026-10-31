import Foundation
import HealthKit

/// `SleepActivityReading` sobre `HKHealthStore` (T-33). **Solo lee**: no hay ninguna llamada a `save`/`delete` y la
/// autorización se pide con `toShare` vacío. Salud oculta si el usuario negó la lectura: una consulta sin resultados
/// y un permiso negado se ven igual, y ambos dan una lista vacía.
struct HealthKitSleepActivityReader: SleepActivityReading {
    private static let sleepType = HKCategoryType(.sleepAnalysis)
    private static let stepType = HKQuantityType(.stepCount)

    private var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else { return }
        try? await HKHealthStore().requestAuthorization(toShare: [], read: [Self.sleepType, Self.stepType])
    }

    func sleepNights(from: Date, to: Date, timeZone: TimeZone) async -> [SleepNight] {
        guard isAvailable, to > from else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: Self.sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: HKHealthStore()) else { return [] }
        let segments = samples.compactMap { sample -> SleepSegment? in
            guard let stage = Self.stage(sample.value) else { return nil }
            return SleepSegment(start: sample.startDate, end: sample.endDate, stage: stage,
                                source: sample.sourceRevision.source.bundleIdentifier)
        }
        return SleepNightGrouper.nights(from: segments, timeZone: timeZone)
    }

    func dailySteps(from: Date, to: Date, timeZone: TimeZone) async -> [DailySteps] {
        guard isAvailable, to > from else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let anchor = calendar.startOfDay(for: from)
        let predicate = HKSamplePredicate.quantitySample(
            type: Self.stepType, predicate: HKQuery.predicateForSamples(withStart: anchor, end: to))
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate, options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
        guard let collection = try? await descriptor.result(for: HKHealthStore()) else { return [] }
        let intervals = collection.statistics().compactMap { statistics -> (start: Date, steps: Double)? in
            statistics.sumQuantity().map { (statistics.startDate, $0.doubleValue(for: .count())) }
        }
        return DailySteps.days(from: intervals, timeZone: timeZone)
    }

    private static func stage(_ value: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: .inBed
        case .asleepUnspecified: .asleepUnspecified
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepREM: .rem
        case .awake: .awake
        case .none: nil
        @unknown default: nil
        }
    }
}
