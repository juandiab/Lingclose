import Foundation
import Testing
import LingoCore
@testable import LingoScan

struct LiveTodayDataSourceTests {
    static let activation: Int64 = 1_800_000_000 - 3 * 3_600
    static let warmup = 60

    private func makeStore() async throws -> SQLiteStore {
        let path = FileManager.default.temporaryDirectory
            .appending(path: "t08b-today-\(UUID().uuidString).sqlite").path(percentEncoded: false)
        let store = try SQLiteStore(path: path)
        try await store.upsertSession(SensorSessionRecord(
            sessionID: "t08b-session", sensorFamily: .lingo, productType: 9, securityVersion: 3,
            sensorSerialHash: String(repeating: "0", count: 64), synthetic: true, sensorSerialRedacted: "SYN",
            warmupMinutes: Self.warmup, wearMinutes: 20_160, activationTimeEpochS: Self.activation,
            activationTimeSource: .command, activatedByAppID: "lingoscan-tests", activationSource: .thisApp,
            activationState: .authenticated, receiverIDPresent: true, lastLifeCount: 122
        ))
        try await store.insertReadings([
            reading(lifeCount: 120, value: 101, qualityFlag: false),
            reading(lifeCount: 121, value: 104, qualityFlag: false),
            reading(lifeCount: 122, value: 180, qualityFlag: true),
        ])
        return store
    }

    private func reading(lifeCount: Int, value: Int, qualityFlag: Bool) -> GlucoseReading {
        let raw = qualityFlag
            ? RawReading(capped: value, uncapped: value, trend: 0, qualityFlag: true, channel: 1)
            : RawReading(capped: value, uncapped: value, trend: 3, rangeBits: 0x4000, qualityFlag: false, channel: 1)
        let eligibility = LingoScanV1Policy.evaluate(
            raw: raw, lifeCount: lifeCount, warmupMinutes: Self.warmup,
            synthetic: true, deleted: false, inSyntheticPackage: true
        )
        let measuredAt = MeasuredAt.compute(activationEpoch: Self.activation, lifeCount: lifeCount)
        return GlucoseReading(
            sessionID: "t08b-session", lifeCount: lifeCount, measuredAt: measuredAt,
            receivedAt: measuredAt.adding(seconds: 1), tzAtCapture: "America/Bogota", origin: .live,
            value: LingoScanV1Policy.value(for: raw, eligibility: eligibility), raw: raw,
            eligibility: eligibility, synthetic: true
        )
    }

    private func source(_ store: SQLiteStore) -> LiveTodayDataSource {
        let now = Date(timeIntervalSince1970: TimeInterval(Self.activation + 130 * 60))
        return LiveTodayDataSource(store: store, coordinator: nil, clock: { now })
    }

    @Test func rangeReturnsAllThreeIncludingExcluded() async throws {
        let store = try await makeStore()
        let all = try await source(store).readings(in: UTCInstant(epochSeconds: Self.activation)...UTCInstant(epochSeconds: Self.activation + 200 * 60))
        #expect(all.count == 3)
        #expect(all.filter { !$0.eligibility.isEligible }.count == 1)
    }

    @Test func latestEligibleSkipsTheExcludedNewerReading() async throws {
        let store = try await makeStore()
        let latest = try #require(try await source(store).latestEligibleReading())
        #expect(latest.lifeCount == 121)
        #expect(latest.value == 104)
    }

    @MainActor
    @Test func viewModelShowsOnlyEligiblePointsFromTheStore() async throws {
        let store = try await makeStore()
        let data = source(store)
        let now = data.clock()
        let model = TodayViewModel(dataSource: data, sensorSource: PreviewData(sensorState: .noSensor), clock: { now })
        await model.refresh()
        #expect(model.points.count == 2)
        #expect(model.latestValue == 104)
        #expect(!model.hasNoData)
    }

    @MainActor
    @Test func emptyStoreHasNoData() async throws {
        let path = FileManager.default.temporaryDirectory
            .appending(path: "t08b-empty-\(UUID().uuidString).sqlite").path(percentEncoded: false)
        let data = LiveTodayDataSource(store: try SQLiteStore(path: path), coordinator: nil)
        let model = TodayViewModel(dataSource: data, sensorSource: PreviewData(sensorState: .noSensor))
        await model.refresh()
        #expect(model.hasNoData)
        #expect(try await data.latestEligibleReading() == nil)
    }

    @Test func coordinatorStateChangeSignalsNewData() async throws {
        let harness = try await CoordinatorHarness()
        let data = LiveTodayDataSource(store: harness.store, coordinator: harness.coordinator)
        let changes = data.changes()
        let box = ValueBox<Bool>()
        let listener = Task {
            for await _ in changes {
                await box.set(true)
                return
            }
        }
        defer { listener.cancel() }
        // Dar tiempo a que el observador se registre antes del cambio de estado.
        try await Task.sleep(for: .milliseconds(200))
        try await harness.coordinator.identify()
        #expect(await eventually(timeout: .seconds(5)) { await box.value == true })
    }
}
