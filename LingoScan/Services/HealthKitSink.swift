import Foundation
import HealthKit
import LingoCore

/// `HealthSink` real sobre `HKHealthStore`. Si HealthKit no está disponible lanza `HealthSinkError.unavailable`.
final class HealthKitSink: HealthSink {
    private let store = HKHealthStore()

    private static let glucoseType = HKQuantityType(.bloodGlucose)
    private static let carbsType = HKQuantityType(.dietaryCarbohydrates)
    private static let mgPerDL = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))

    private var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func authorizationStatus() async -> HealthAuthorizationStatus {
        guard isAvailable else { return .unavailable }
        let statuses = [Self.glucoseType, Self.carbsType].map { store.authorizationStatus(for: $0) }
        if statuses.allSatisfy({ $0 == .sharingAuthorized }) { return .authorized }
        if statuses.contains(.sharingDenied) { return .denied }
        return .notDetermined
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthSinkError.unavailable }
        do {
            try await store.requestAuthorization(
                toShare: [Self.glucoseType, Self.carbsType], read: [HKObjectType.workoutType()])
        } catch {
            throw HealthSinkError.failed(Self.describe(error))
        }
    }

    func write(samples: [HealthSampleSpec]) async throws -> [HealthWriteResult] {
        guard isAvailable else { throw HealthSinkError.unavailable }
        guard await authorizationStatus() == .authorized else { throw HealthSinkError.authorizationDenied }
        let hkSamples = samples.map(Self.makeSample)
        do {
            try await store.save(hkSamples)
            return samples.map { HealthWriteResult(syncIdentifier: $0.syncIdentifier, outcome: .written) }
        } catch let error as HKError where error.code == .errorAuthorizationDenied || error.code == .errorAuthorizationNotDetermined {
            throw HealthSinkError.authorizationDenied
        } catch {
            guard samples.count > 1 else {
                return [HealthWriteResult(syncIdentifier: samples[0].syncIdentifier, outcome: .failed, detail: Self.describe(error))]
            }
            // `save([...])` es atómico: una muestra mala bloquearía a las demás. Se aísla guardando de una en una.
            var results: [HealthWriteResult] = []
            for (spec, sample) in zip(samples, hkSamples) {
                do {
                    try await store.save(sample)
                    results.append(HealthWriteResult(syncIdentifier: spec.syncIdentifier, outcome: .written))
                } catch let error as HKError where error.code == .errorAuthorizationDenied || error.code == .errorAuthorizationNotDetermined {
                    throw HealthSinkError.authorizationDenied
                } catch {
                    results.append(HealthWriteResult(syncIdentifier: spec.syncIdentifier, outcome: .failed, detail: Self.describe(error)))
                }
            }
            return results
        }
    }

    func query(syncIdentifiers: Set<String>) async throws -> Set<String> {
        guard isAvailable else { throw HealthSinkError.unavailable }
        var found: Set<String> = []
        let ids = Array(syncIdentifiers)
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let byID = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: chunk)
            let ours = HKQuery.predicateForObjects(from: HKSource.default())
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [byID, ours])
            for type in [Self.glucoseType, Self.carbsType] {
                do {
                    let descriptor = HKSampleQueryDescriptor(
                        predicates: [.quantitySample(type: type, predicate: predicate)], sortDescriptors: [])
                    for sample in try await descriptor.result(for: store) {
                        if let id = sample.metadata?[HKMetadataKeySyncIdentifier] as? String { found.insert(id) }
                    }
                } catch {
                    throw HealthSinkError.failed(Self.describe(error))
                }
            }
        }
        return found
    }

    func workouts(in range: ClosedRange<UTCInstant>) async throws -> [HealthWorkoutSummary] {
        guard isAvailable else { throw HealthSinkError.unavailable }
        let predicate = HKQuery.predicateForSamples(withStart: range.lowerBound.date, end: range.upperBound.date, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            return try await descriptor.result(for: store).map {
                HealthWorkoutSummary(
                    id: $0.uuid.uuidString.lowercased(), start: UTCInstant($0.startDate), end: UTCInstant($0.endDate),
                    activityTypeRaw: $0.workoutActivityType.rawValue, sourceName: $0.sourceRevision.source.name)
            }
        } catch {
            throw HealthSinkError.failed(Self.describe(error))
        }
    }

    // MARK: - Traducción

    static func makeSample(_ spec: HealthSampleSpec) -> HKQuantitySample {
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: spec.syncIdentifier,
            HKMetadataKeySyncVersion: spec.syncVersion,
            HKMetadataKeyWasUserEntered: spec.wasUserEntered,
        ]
        if let v = spec.sessionID { metadata[HealthSampleSpec.sessionKey] = v }
        if let v = spec.lifeCount { metadata[HealthSampleSpec.lifeCountKey] = v }
        if let v = spec.origin { metadata[HealthSampleSpec.originKey] = v }
        if let v = spec.trend { metadata[HealthSampleSpec.trendKey] = v }
        if let v = spec.note { metadata[HealthSampleSpec.noteKey] = v }
        let type: HKQuantityType
        let quantity: HKQuantity
        switch spec.kind {
        case .glucose:
            type = glucoseType
            quantity = HKQuantity(unit: mgPerDL, doubleValue: spec.value)
        case .carbs:
            type = carbsType
            quantity = HKQuantity(unit: .gram(), doubleValue: spec.value)
        }
        return HKQuantitySample(type: type, quantity: quantity, start: spec.date.date, end: spec.date.date, metadata: metadata)
    }

    private static func describe(_ error: any Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }
}
