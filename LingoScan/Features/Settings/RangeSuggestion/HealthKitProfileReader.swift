import Foundation
import HealthKit

/// `HealthProfileReading` real. Pide permiso de lectura solo para fecha de nacimiento, sexo biológico, masa
/// corporal y altura (aparte de los tipos que escribe `HealthKitSink`). Salud oculta si el usuario negó la
/// lectura de una muestra: una consulta sin resultados y un permiso negado se ven igual, así que ambos se
/// tratan como "no disponible en Salud".
struct HealthKitProfileReader: HealthProfileReading {
    private static let dateOfBirth = HKCharacteristicType(.dateOfBirth)
    private static let biologicalSex = HKCharacteristicType(.biologicalSex)
    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let height = HKQuantityType(.height)
    private static let readTypes: Set<HKObjectType> = [dateOfBirth, biologicalSex, bodyMass, height]

    func readProfile() async throws -> HealthProfile {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthProfileError.unavailable }
        let store = HKHealthStore()
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
        } catch {
            let ns = error as NSError
            throw HealthProfileError.authorizationFailed("\(ns.domain) \(ns.code)")
        }
        var profile = HealthProfile()
        if let components = try? store.dateOfBirthComponents(), let birth = Calendar.current.date(from: components) {
            let years = Calendar.current.dateComponents([.year], from: birth, to: .now).year
            if let years, (0...130).contains(years) { profile.ageYears = years }
        }
        if let sex = try? store.biologicalSex().biologicalSex {
            profile.biologicalSex = switch sex {
            case .female: .female
            case .male: .male
            case .other: .other
            case .notSet: nil
            @unknown default: nil
            }
        }
        if let kg = await Self.latestValue(of: Self.bodyMass, unit: .gramUnit(with: .kilo), in: store), (20...400).contains(kg) {
            profile.weightKg = kg
        }
        if let cm = await Self.latestValue(of: Self.height, unit: .meterUnit(with: .centi), in: store), (50...260).contains(cm) {
            profile.heightCm = cm
        }
        return profile
    }

    private static func latestValue(of type: HKQuantityType, unit: HKUnit, in store: HKHealthStore) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: unit)
    }
}
