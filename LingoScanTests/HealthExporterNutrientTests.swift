import Foundation
import HealthKit
import Testing
import LingoCore
@testable import LingoScan

/// Energía, proteína y grasa de las comidas hacia el sink (T-21). Todo sintético.
struct HealthExporterNutrientTests {
    private let writer = HealthExporter.writerAppID

    private struct Rig {
        let store: SQLiteStore
        let sink: InMemoryHealthSink
        let exporter: HealthExporter
    }

    private func rig() throws -> Rig {
        let store = try HealthFixtures.makeStore()
        let sink = InMemoryHealthSink()
        let clock = HealthTestClock()
        let exporter = HealthExporter(store: store, sink: sink, now: { clock.now },
                                      backoff: HealthBackoff(baseSeconds: 60, maxSeconds: 3600))
        return Rig(store: store, sink: sink, exporter: exporter)
    }

    @discardableResult
    private func saveMeal(_ r: Rig, base: Nutrients, multiplier: Double = 1.0, overrides: Nutrients = .unknown) async throws -> DiaryEvent {
        let event = HealthFixtures.meal(carbs: nil)
        let record = MealNutritionRecord(
            eventID: event.eventID, source: .manual, kind: .food, name: "Plato de prueba",
            basis: .estimatedServing(description: "1 plato", grams: 200), baseNutrients: base, multiplier: multiplier,
            overrides: overrides, updatedAt: event.updatedAt)
        try await r.store.saveMeal(event: event, nutrition: record)
        return event
    }

    @Test func threeNewTypesReachTheSinkWithCorrectUnitsAndValues() async throws {
        let r = try rig()
        let meal = try await saveMeal(r, base: Nutrients(kcal: 200, carbsG: 30, proteinG: 10, fatG: 5), multiplier: 1.5)
        let summary = await r.exporter.drain()
        #expect(summary.written == 4 && summary.failed == 0)
        let id = meal.eventID
        let samples = await r.sink.samples
        #expect(Set(samples.keys) == [id, "\(id):energy_kcal", "\(id):protein_g", "\(id):fat_g"])
        let energy = try #require(samples["\(id):energy_kcal"])
        let protein = try #require(samples["\(id):protein_g"])
        let fat = try #require(samples["\(id):fat_g"])
        #expect(energy.kind == .energyKcal && energy.unit == .kilocalories && energy.value == 300)
        #expect(protein.kind == .proteinG && protein.unit == .grams && protein.value == 15)
        #expect(fat.kind == .fatG && fat.unit == .grams && fat.value == 7.5)
        #expect(try #require(samples[id]).value == 45)
        for spec in [energy, protein, fat] {
            #expect(spec.wasUserEntered == false && spec.date == meal.at && spec.syncVersion == meal.revision)
        }
        for kind in [HealthSubjectKind.carbs, .energyKcal, .proteinG, .fatG] {
            #expect(try await r.store.derivedHealthState(subjectID: id, writerAppID: writer, subjectKind: kind, currentVersion: 1) == .written)
        }
        #expect(await r.exporter.pendingCount == 0)
    }

    @Test func unknownNutrientProducesNoSampleAndKnownZeroDoes() async throws {
        let r = try rig()
        let meal = try await saveMeal(r, base: Nutrients(kcal: 120, carbsG: 20, proteinG: nil, fatG: 0))
        let summary = await r.exporter.drain()
        #expect(summary.written == 3)
        let samples = await r.sink.samples
        let id = meal.eventID
        #expect(samples["\(id):protein_g"] == nil, "desconocido nunca se escribe como 0")
        #expect(try #require(samples["\(id):fat_g"]).value == 0, "un 0 conocido sí se exporta")
        #expect(try await r.store.ledgerEntries(subjectID: id, subjectKind: .proteinG).isEmpty)
        #expect(await r.exporter.pendingCount == 0)
    }

    @Test func manualOverridesWinOverTheScaledBase() async throws {
        let r = try rig()
        let meal = try await saveMeal(r, base: Nutrients(kcal: 200, carbsG: 30, proteinG: 10, fatG: 5), multiplier: 2.0,
                                      overrides: Nutrients(kcal: 350))
        await r.exporter.drain()
        let samples = await r.sink.samples
        #expect(try #require(samples["\(meal.eventID):energy_kcal"]).value == 350)
        #expect(try #require(samples["\(meal.eventID):protein_g"]).value == 20)
    }

    @Test func sinkDenyingOnlyFatFailsThatSampleWithoutBlockingGlucose() async throws {
        let r = try rig()
        let session = HealthFixtures.session()
        try await r.store.upsertSession(session)
        let reading = HealthFixtures.reading(session, lifeCount: 100)
        try await r.store.insertReadings([reading])
        let meal = try await saveMeal(r, base: Nutrients(kcal: 200, carbsG: 30, proteinG: 10, fatG: 5))
        await r.sink.setDenied([.fatG])

        let summary = await r.exporter.drain()
        #expect(summary.written == 4 && summary.failed == 1 && !summary.stoppedByError)
        let samples = await r.sink.samples
        #expect(Set(samples.keys) == [reading.recordID, meal.eventID, "\(meal.eventID):energy_kcal", "\(meal.eventID):protein_g"])
        #expect(try await r.store.derivedHealthState(subjectID: reading.recordID, writerAppID: writer) == .written)
        #expect(try await r.store.derivedHealthState(subjectID: meal.eventID, writerAppID: writer, subjectKind: .fatG,
                                                     currentVersion: meal.revision) == .failed)
        #expect(try await r.store.derivedHealthState(subjectID: meal.eventID, writerAppID: writer, subjectKind: .energyKcal,
                                                     currentVersion: meal.revision) == .written)
        #expect(await r.exporter.lastError != nil)
        #expect(await r.exporter.pendingCount == 1, "solo la grasa queda pendiente")

        // Con el permiso restituido y pasada la espera, la grasa llega sin repetir lo demás.
        await r.sink.setDenied([])
        let retry = await r.exporter.drain(force: true)
        #expect(retry.written == 1 && retry.failed == 0)
        #expect(try #require(await r.sink.samples["\(meal.eventID):fat_g"]).value == 5)
        #expect(await r.exporter.pendingCount == 0)
    }

    @Test func healthKitSampleUsesTheRightQuantityTypeAndUnit() {
        func sample(_ kind: HealthSubjectKind, _ value: Double) -> HKQuantitySample {
            HealthKitSink.makeSample(HealthSampleSpec(kind: kind, value: value, date: UTCInstant(epochSeconds: 1_800_000_000),
                                                      syncIdentifier: "id:\(kind.rawValue)", syncVersion: 2))
        }
        let energy = sample(.energyKcal, 300)
        #expect(energy.quantityType == HKQuantityType(.dietaryEnergyConsumed))
        #expect(energy.quantity.doubleValue(for: .kilocalorie()) == 300)
        let protein = sample(.proteinG, 15)
        #expect(protein.quantityType == HKQuantityType(.dietaryProtein))
        #expect(protein.quantity.doubleValue(for: .gram()) == 15)
        let fat = sample(.fatG, 7.5)
        #expect(fat.quantityType == HKQuantityType(.dietaryFatTotal))
        #expect(fat.quantity.doubleValue(for: .gram()) == 7.5)
        #expect(fat.metadata?[HKMetadataKeySyncIdentifier] as? String == "id:fat_g")
        #expect(fat.metadata?[HKMetadataKeyWasUserEntered] as? Bool == false)
    }
}
