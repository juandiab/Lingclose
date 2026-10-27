import Foundation
import HealthKit
import LingoCore

/// `WorkoutSource` sobre `HKHealthStore`. **Solo lee**: no hay ninguna llamada a `save`/`delete` en este tipo y la
/// autorización se pide con `toShare` vacío.
final class HealthKitWorkoutSource: WorkoutSource {
    private let store = HKHealthStore()

    private static let workoutType = HKObjectType.workoutType()
    private static let energyType = HKQuantityType(.activeEnergyBurned)
    private static let heartRateType = HKQuantityType(.heartRate)
    /// Distancias posibles de un entrenamiento; se usa la primera que tenga suma.
    private static let distanceTypes: [HKQuantityType] = [
        HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming),
        HKQuantityType(.distanceWheelchair), HKQuantityType(.distanceDownhillSnowSports), HKQuantityType(.distanceRowing),
        HKQuantityType(.distancePaddleSports), HKQuantityType(.distanceCrossCountrySkiing), HKQuantityType(.distanceSkatingSports),
    ]
    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    private var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestReadAuthorization() async throws {
        guard isAvailable else { return }
        let read: Set<HKObjectType> = Set([Self.workoutType, Self.energyType, Self.heartRateType] + Self.distanceTypes)
        try await store.requestAuthorization(toShare: [], read: read)
    }

    func workouts(since anchor: Data?, notBefore: Date) async throws -> WorkoutBatch {
        guard isAvailable else { return WorkoutBatch(workouts: [], anchor: nil) }
        let previous = anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        let predicate = HKQuery.predicateForSamples(withStart: notBefore, end: nil, options: .strictStartDate)
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.workout(predicate)], anchor: previous)
        let result = try await descriptor.result(for: store)
        let newAnchor = try? NSKeyedArchiver.archivedData(withRootObject: result.newAnchor, requiringSecureCoding: true)
        return WorkoutBatch(workouts: result.addedSamples.map(Self.summary), anchor: newAnchor)
    }

    func observeNewWorkouts() -> AsyncStream<WorkoutChangeNotice> {
        let (stream, continuation) = AsyncStream<WorkoutChangeNotice>.makeStream(bufferingPolicy: .bufferingNewest(4))
        guard isAvailable else {
            continuation.finish()
            return stream
        }
        let query = HKObserverQuery(sampleType: Self.workoutType, predicate: nil) { _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            let box = CompletionBox(completion)
            continuation.yield(WorkoutChangeNotice { box.call() })
        }
        let store = store
        store.execute(query)
        // Despierta la app cuando el Watch guarda un entrenamiento. Sin permiso o sin la capacidad, falla en silencio.
        store.enableBackgroundDelivery(for: Self.workoutType, frequency: .immediate) { _, _ in }
        continuation.onTermination = { _ in store.stop(query) }
        return stream
    }

    // MARK: - Traducción

    private static func summary(_ w: HKWorkout) -> WorkoutSummary {
        let distance = distanceTypes.lazy
            .compactMap { w.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }
            .first
        return WorkoutSummary(
            uuid: w.uuid.uuidString.lowercased(),
            activityName: w.workoutActivityType.displayName,
            start: UTCInstant(w.startDate), end: UTCInstant(w.endDate),
            durationMin: Int((w.duration / 60).rounded()),
            activeEnergyKcal: w.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            distanceMeters: distance,
            averageHeartRate: w.statistics(for: heartRateType)?.averageQuantity()?.doubleValue(for: bpm),
            sourceName: w.sourceRevision.source.name)
    }

    /// El completion handler de `HKObserverQuery` no es `Sendable`; HealthKit admite llamarlo desde cualquier hilo.
    private final class CompletionBox: @unchecked Sendable {
        private let completion: () -> Void
        init(_ completion: @escaping () -> Void) { self.completion = completion }
        func call() { completion() }
    }
}
