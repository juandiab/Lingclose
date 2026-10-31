import Foundation
import HealthKit

/// `BodyCompositionReading` sobre `HKHealthStore` (T-33, adenda 1). **Solo lee** (`toShare` vacío; ninguna llamada a
/// `save`/`delete`). Lee lo que una báscula de bioimpedancia escribe en Salud con tipos estándar; el sexo, la edad y la
/// altura siguen en `HealthKitProfileReader`.
struct HealthKitBodyCompositionReader: BodyCompositionReading {
    private static let types: [BodyMetric: (type: HKQuantityType, unit: HKUnit, scale: Double)] = [
        .weight: (HKQuantityType(.bodyMass), .gramUnit(with: .kilo), 1),
        // HealthKit guarda el porcentaje como fracción (0,22 = 22 %).
        .bodyFat: (HKQuantityType(.bodyFatPercentage), .percent(), 100),
        .leanMass: (HKQuantityType(.leanBodyMass), .gramUnit(with: .kilo), 1),
        .bmi: (HKQuantityType(.bodyMassIndex), .count(), 1),
        .waist: (HKQuantityType(.waistCircumference), .meterUnit(with: .centi), 1),
    ]

    private var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else { return }
        let read: Set<HKObjectType> = Set(Self.types.values.map(\.type))
        try? await HKHealthStore().requestAuthorization(toShare: [], read: read)
    }

    func bodyComposition(from: Date, to: Date, timeZone: TimeZone) async -> BodyComposition {
        guard isAvailable, to > from else { return .empty }
        let store = HKHealthStore()
        var latest: [BodyMetric: BodyMeasurement] = [:]
        var inPeriod: [BodyMetric: [BodyMeasurement]] = [:]
        for metric in BodyMetric.allCases {
            guard let spec = Self.types[metric] else { continue }
            let untilEnd = HKQuery.predicateForSamples(withStart: nil, end: to)
            let newest = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: spec.type, predicate: untilEnd)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
            if let sample = try? await newest.result(for: store).first {
                latest[metric] = BodyMeasurement(date: sample.endDate, value: sample.quantity.doubleValue(for: spec.unit) * spec.scale)
            }
            guard BodyMetric.trended.contains(metric) else { continue }
            let period = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: spec.type, predicate: HKQuery.predicateForSamples(withStart: from, end: to))],
                sortDescriptors: [SortDescriptor(\.endDate)])
            if let samples = try? await period.result(for: store) {
                inPeriod[metric] = samples.map {
                    BodyMeasurement(date: $0.endDate, value: $0.quantity.doubleValue(for: spec.unit) * spec.scale)
                }
            }
        }
        return BodyComposition.make(latest: latest, inPeriod: inPeriod, timeZone: timeZone)
    }

    /// Cada muestra de cada medida dentro de `[from, to)`, para la tabla del reporte en PDF (T-34). Solo lectura.
    func bodyMeasurementSeries(from: Date, to: Date) async -> BodyMeasurementSeries {
        guard isAvailable, to > from else { return .empty }
        let store = HKHealthStore()
        var series = BodyMeasurementSeries()
        for metric in BodyMetric.allCases {
            guard let spec = Self.types[metric] else { continue }
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: spec.type, predicate: HKQuery.predicateForSamples(withStart: from, end: to))],
                sortDescriptors: [SortDescriptor(\.endDate)])
            if let found = try? await descriptor.result(for: store) {
                series.samples[metric] = found.map {
                    BodyMeasurement(date: $0.endDate, value: $0.quantity.doubleValue(for: spec.unit) * spec.scale)
                }
            }
        }
        return series
    }
}
