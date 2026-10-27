import Foundation
import Synchronization
import Testing
import LingoCore
@testable import LingoScan

final class RecordingScheduler: NotificationScheduling {
    struct Log: Sendable {
        var scheduled: [AlarmNotification] = []
        var cancelled: [[String]] = []
        var status: AlarmPermission = .authorized
        var grant = true
    }
    private let log = Mutex(Log())

    var scheduled: [AlarmNotification] { log.withLock { $0.scheduled } }
    var cancelled: [[String]] { log.withLock { $0.cancelled } }
    func setStatus(_ status: AlarmPermission) { log.withLock { $0.status = status } }
    func setGrant(_ grant: Bool) { log.withLock { $0.grant = grant } }
    func authorizationStatus() async -> AlarmPermission { log.withLock { $0.status } }
    func requestAuthorization() async throws -> Bool {
        log.withLock { l in
            if l.grant { l.status = .authorized } else { l.status = .denied }
            return l.grant
        }
    }
    func schedule(_ n: AlarmNotification) async throws { log.withLock { $0.scheduled.append(n) } }
    func cancel(ids: [String]) async { log.withLock { $0.cancelled.append(ids) } }
}

struct AlarmServiceTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeService(_ scheduler: RecordingScheduler, clock: TestClock = TestClock(start: t0)) -> (AlarmService, TestClock) {
        let defaults = UserDefaults(suiteName: "AlarmServiceTests-\(UUID().uuidString)")!
        return (AlarmService(settings: AlarmSettingsStore(defaults: defaults), scheduler: scheduler, now: { clock.now }), clock)
    }

    static func session() -> SensorSessionRecord {
        SensorSessionRecord(
            sessionID: "alarm-test-session", sensorFamily: .lingo, productType: 9, securityVersion: 3,
            sensorSerialHash: String(repeating: "ab", count: 32), synthetic: false,
            sensorSerialRedacted: "XYZ…", firmwareHex: "01020304", warmupMinutes: 60, wearMinutes: 20_160,
            activationTimeEpochS: 1_799_000_000, activationTimeSource: .nfcResponse, activatedByAppID: "com.otalvaro.lingoscan",
            activationSource: .thisApp, activationState: .authenticated, receiverIDPresent: true
        )
    }

    private func summary(_ value: Int?, lc: Int, at clock: TestClock, eligible: Bool = true, origin: ReadingOrigin = .live) -> ReadingSummary {
        let session = Self.session()
        var raw = RawReading(capped: value, uncapped: value, trend: nil, temperatureCenti: nil, qualityFlag: !eligible, channel: nil)
        if value == nil { raw = RawReading(capped: nil, uncapped: nil, trend: nil, temperatureCenti: nil, qualityFlag: true, channel: nil) }
        var reading = GlucoseReading.make(session: session, lifeCount: lc, raw: raw, origin: origin,
                                          receivedAt: UTCInstant(clock.now), tzAtCapture: "UTC")
        reading.measuredAt = UTCInstant(clock.now)
        return ReadingSummary(reading)
    }

    @Test func lowReadingSchedulesTimeSensitiveNotificationAndNoData() async {
        let scheduler = RecordingScheduler()
        let (service, clock) = makeService(scheduler)
        await service.ingest(AlarmSample(valueMgdl: 60, measuredAt: UTCInstant(clock.now), lifeCount: 100))
        let sent = scheduler.scheduled
        #expect(sent.count == 2)
        #expect(sent[0].kind == .low && sent[0].timeSensitive)
        #expect(sent[1].kind == .noData && !sent[1].timeSensitive && sent[1].delay == 20 * 60)
        #expect(sent[1].id == AlarmService.noDataID)
    }

    @Test func highReadingIsNotTimeSensitive() async {
        let scheduler = RecordingScheduler()
        let (service, clock) = makeService(scheduler)
        await service.ingest(AlarmSample(valueMgdl: 250, measuredAt: UTCInstant(clock.now)))
        #expect(scheduler.scheduled.first?.kind == .high)
        #expect(scheduler.scheduled.first?.timeSensitive == false)
    }

    @Test func eachValidReadingReplacesTheNoDataNotification() async {
        let scheduler = RecordingScheduler()
        let (service, clock) = makeService(scheduler)
        await service.ingest(AlarmSample(valueMgdl: 100, measuredAt: UTCInstant(clock.now)))
        clock.advance(by: .seconds(60))
        await service.ingest(AlarmSample(valueMgdl: 100, measuredAt: UTCInstant(clock.now)))
        #expect(scheduler.cancelled.filter { $0 == [AlarmService.noDataID] }.count == 2)
        #expect(scheduler.scheduled.filter { $0.kind == .noData }.count == 2)
        #expect(scheduler.scheduled.allSatisfy { $0.kind == .noData })
    }

    @Test func repeatedFrameOfSameMinuteIsIgnored() async {
        let scheduler = RecordingScheduler()
        let (service, clock) = makeService(scheduler)
        let sample = AlarmSample(valueMgdl: 60, measuredAt: UTCInstant(clock.now))
        await service.ingest(sample)
        await service.ingest(sample)
        #expect(scheduler.scheduled.filter { $0.kind == .low }.count == 1)
    }

    @Test func hysteresisBlocksRepeatWithin15Minutes() async {
        let scheduler = RecordingScheduler()
        let (service, clock) = makeService(scheduler)
        for _ in 0..<5 {
            await service.ingest(AlarmSample(valueMgdl: 60, measuredAt: UTCInstant(clock.now)))
            clock.advance(by: .seconds(60))
        }
        #expect(scheduler.scheduled.filter { $0.kind == .low }.count == 1)
    }

    @Test func pausedStateCancelsNoDataAndSilencesAlarms() async {
        let scheduler = RecordingScheduler()
        let (service, clock) = makeService(scheduler)
        await service.ingest(AlarmSample(valueMgdl: 100, measuredAt: UTCInstant(clock.now)))
        await service.handle(.paused)
        #expect(scheduler.cancelled.last == [AlarmService.noDataID])
        let before = scheduler.scheduled.count
        clock.advance(by: .seconds(60))
        await service.ingest(AlarmSample(valueMgdl: 40, measuredAt: UTCInstant(clock.now)))
        #expect(scheduler.scheduled.count == before)
    }

    @Test func streamingStateFeedsAlarmsOnlyWhenEligibleAndLive() async {
        let scheduler = RecordingScheduler()
        let (service, clock) = makeService(scheduler)
        await service.handle(.streaming(last: summary(60, lc: 70, at: clock, eligible: false)))
        await service.handle(.streaming(last: summary(60, lc: 71, at: clock, origin: .backfillHistory)))
        #expect(scheduler.scheduled.isEmpty)
        await service.handle(.streaming(last: summary(60, lc: 72, at: clock)))
        #expect(scheduler.scheduled.first?.kind == .low)
    }

    @Test func endedSessionCancelsNoData() async {
        let scheduler = RecordingScheduler()
        let (service, clock) = makeService(scheduler)
        await service.ingest(AlarmSample(valueMgdl: 100, measuredAt: UTCInstant(clock.now)))
        await service.handle(.ended(reason: .expired))
        #expect(scheduler.cancelled.last == [AlarmService.noDataID])
    }

    @Test func deniedPermissionSchedulesNothing() async {
        let scheduler = RecordingScheduler()
        scheduler.setStatus(.denied)
        let (service, clock) = makeService(scheduler)
        await service.ingest(AlarmSample(valueMgdl: 40, measuredAt: UTCInstant(clock.now)))
        #expect(scheduler.scheduled.isEmpty)
        #expect(await service.permission() == .denied)
    }

    @Test func requestPermissionReflectsScheduler() async {
        let scheduler = RecordingScheduler()
        scheduler.setStatus(.notDetermined)
        let (service, _) = makeService(scheduler)
        #expect(await service.requestPermission())
        #expect(await service.permission() == .authorized)
    }

    @Test func settingsStoreRoundTripsAndClamps() {
        let defaults = UserDefaults(suiteName: "AlarmStoreTests-\(UUID().uuidString)")!
        let store = AlarmSettingsStore(defaults: defaults)
        #expect(store.load() == .default)
        store.save(AlarmSettings(lowMgdl: 80, highMgdl: 999, noDataMinutes: 30, lowEnabled: false))
        let loaded = store.load()
        #expect(loaded.lowMgdl == 80 && loaded.highMgdl == 400 && loaded.noDataMinutes == 30 && !loaded.lowEnabled)
    }

    @Test func appGroupIdentifierMatchesEntitlement() {
        #expect(AlarmSettingsStore.appGroupID == "group.com.otalvaro.lingoscan")
    }
}
