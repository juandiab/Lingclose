#if LINGOSCAN_HEALTH_SIM_TESTS
import HealthKit
import XCTest
import LingoCore
@testable import LingoScan

/// Integración contra el `HKHealthStore` real del simulador. Solo se compila con `-DLINGOSCAN_HEALTH_SIM_TESTS`
/// (esquema `LingoScanHealthSim`); la build instalable no la contiene ni tiene un interruptor equivalente.
///
/// La primera ejecución en un simulador limpio muestra la hoja de permisos de Salud: hay que aceptar "Activar todo".
/// Después el permiso persiste mientras la app no se desinstale del simulador.
final class HealthKitSimulatorTests: XCTestCase {
    private let hk = HKHealthStore()
    private let sink = HealthKitSink()
    private let glucose = HKQuantityType(.bloodGlucose)
    private let carbs = HKQuantityType(.dietaryCarbohydrates)
    private var sessionID = ""
    private var eventIDs: [String] = []
    private var identifiers: [String] = []

    override func setUp() async throws {
        try XCTSkipUnless(HKHealthStore.isHealthDataAvailable(), "HealthKit no está disponible en este simulador")
        sessionID = "healthsim-" + UUID().uuidString.lowercased()
        try await sink.requestAuthorization()
        let status = await sink.authorizationStatus()
        XCTAssertEqual(status, .authorized, "Acepta la hoja de permisos de Salud (Activar todo) y repite")
    }

    override func tearDown() async throws {
        guard HKHealthStore.isHealthDataAvailable(), !identifiers.isEmpty else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: identifiers)
        try? await hk.deleteObjects(of: glucose, predicate: predicate)
        try? await hk.deleteObjects(of: carbs, predicate: predicate)
    }

    private func makeStore(readings: Int) async throws -> (SQLiteStore, SensorSessionRecord) {
        let store = try HealthFixtures.makeStore()
        let session = HealthFixtures.session(id: sessionID)
        try await store.upsertSession(session)
        let all = (0..<readings).map { HealthFixtures.reading(session, lifeCount: 100 + $0, value: 90 + $0 % 40) }
        try await store.insertReadings(all)
        identifiers += all.map(\.recordID)
        return (store, session)
    }

    private func samples(of type: HKQuantityType, ids: [String]) async throws -> [HKQuantitySample] {
        let byID = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: ids)
        return try await HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: byID)], sortDescriptors: [])
            .result(for: hk)
    }

    func testHundredReadingsRoundTripWithoutDuplicates() async throws {
        let (store, session) = try await makeStore(readings: 100)
        let exporter = HealthExporter(store: store, sink: sink)
        let first = await exporter.drain()
        XCTAssertEqual(first.written, 100)
        let again = await exporter.drain()
        XCTAssertEqual(again.written, 0)

        let found = try await samples(of: glucose, ids: identifiers)
        XCTAssertEqual(found.count, 100, "reintento no duplica")
        let mgdl = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        for sample in found {
            let meta = try XCTUnwrap(sample.metadata)
            XCTAssertEqual(meta[HKMetadataKeyWasUserEntered] as? Bool, false)
            XCTAssertEqual(meta[HKMetadataKeySyncVersion] as? Int, 1)
            XCTAssertEqual(meta[HealthSampleSpec.sessionKey] as? String, session.sessionID)
            XCTAssertEqual(meta[HealthSampleSpec.originKey] as? String, "live")
            XCTAssertNotNil(meta[HealthSampleSpec.lifeCountKey])
            XCTAssertEqual(sample.startDate, sample.endDate)
            let value = sample.quantity.doubleValue(for: mgdl)
            XCTAssertTrue((90..<130).contains(Int(value.rounded())))
        }
        let pending = await exporter.pendingCount
        XCTAssertEqual(pending, 0)
    }

    func testUnknownReconcilesAgainstRealStore() async throws {
        let (store, session) = try await makeStore(readings: 2)
        let all = try await store.readings(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 3_000_000_000))
        let landed = all[0]
        // Health recibió la muestra, pero el ledger solo registró `unknown`.
        let exportable = try XCTUnwrap(HealthExportable(reading: landed, session: session))
        _ = try await sink.write(samples: [HealthSampleMapper.spec(for: exportable)])
        for s in all {
            try await store.appendLedger(HealthLedgerEntry(
                attemptID: UUID().uuidString.lowercased(), subjectID: s.recordID, subjectKind: .glucose,
                writerAppID: HealthExporter.writerAppID, syncIdentifier: s.recordID, syncVersion: s.revision,
                exportedAt: UTCInstant(Date()), result: .unknown))
        }
        let exporter = HealthExporter(store: store, sink: sink)
        let summary = await exporter.drain()
        XCTAssertEqual(summary.reconciled, 1)
        XCTAssertEqual(summary.written, 1)
        let found = try await samples(of: glucose, ids: all.map(\.recordID))
        XCTAssertEqual(found.count, 2)
        let state = try await store.derivedHealthState(subjectID: landed.recordID, writerAppID: HealthExporter.writerAppID)
        XCTAssertEqual(state, .written)
    }

    func testCarbohydratesWithNoteAndExclusions() async throws {
        let store = try HealthFixtures.makeStore()
        let meal = HealthFixtures.meal(carbs: 45, text: "arepa con huevo (prueba simulador)")
        identifiers.append(meal.eventID)
        try await store.upsertEvent(meal)
        try await store.upsertEvent(HealthFixtures.meal(kind: .note))
        let synthetic = HealthFixtures.meal(synthetic: true)
        identifiers.append(synthetic.eventID)
        try await store.upsertEvent(synthetic)
        let exporter = HealthExporter(store: store, sink: sink)
        let summary = await exporter.drain()
        XCTAssertEqual(summary.written, 1)
        let found = try await samples(of: carbs, ids: identifiers)
        XCTAssertEqual(found.count, 1)
        let sample = try XCTUnwrap(found.first)
        XCTAssertEqual(sample.quantity.doubleValue(for: .gram()), 45)
        XCTAssertEqual(sample.metadata?[HealthSampleSpec.noteKey] as? String, "arepa con huevo (prueba simulador)")
        XCTAssertEqual(sample.metadata?[HKMetadataKeySyncIdentifier] as? String, meal.eventID)
    }

    func testQueryOnlySeesOwnSamplesAndWorkoutsReadDoesNotThrow() async throws {
        let found = try await sink.query(syncIdentifiers: ["no-existe-\(UUID().uuidString)"])
        XCTAssertTrue(found.isEmpty)
        let now = UTCInstant(Date())
        let workouts = try await sink.workouts(in: now.adding(seconds: -86_400)...now)
        XCTAssertNotNil(workouts)
    }
}
#endif
