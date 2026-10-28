import Foundation
import Synchronization
import Testing
import LingoCore
@testable import LingoScan

/// Notificador falso: registra lo entregado y lo programado, sin `UNUserNotificationCenter`.
final class RecordingAlertNotifier: AlertNotifying {
    struct Log: Sendable {
        var delivered: [AlertNotification] = []
        var scheduled: [(AlertNotification, Date)] = []
        var cancelled: [String] = []
        var permission: AlertPermission = .authorized
    }
    private let log = Mutex(Log())

    var delivered: [AlertNotification] { log.withLock { $0.delivered } }
    var scheduled: [(AlertNotification, Date)] { log.withLock { $0.scheduled } }
    var cancelled: [String] { log.withLock { $0.cancelled } }
    func setPermission(_ p: AlertPermission) { log.withLock { $0.permission = p } }

    func authorization() async -> AlertPermission { log.withLock { $0.permission } }
    func requestAuthorization() async -> Bool { log.withLock { $0.permission = .authorized; return true } }
    func deliver(_ notification: AlertNotification) async throws { log.withLock { $0.delivered.append(notification) } }
    func schedule(_ notification: AlertNotification, at date: Date) async throws { log.withLock { $0.scheduled.append((notification, date)) } }
    func cancelPending(ids: [String]) async { log.withLock { $0.cancelled += ids } }
}

/// Lecturas y registro en memoria.
actor InMemoryAlertStore: AlertDataStore {
    private(set) var samples: [BasicStats.Sample] = []
    private(set) var logs: [String] = []

    func add(_ value: Int, at date: Date) { samples.append(BasicStats.Sample(measuredAt: UTCInstant(date), valueMgdl: value)) }

    func alertSamples(in range: ClosedRange<UTCInstant>) async throws -> [BasicStats.Sample] {
        samples.filter { range.contains($0.measuredAt) }.sorted { $0.measuredAt < $1.measuredAt }
    }

    func logAlert(_ level: EventLogLevel, _ message: LogMessage) async { logs.append(message.text) }
}

struct AlertServiceTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func make(store: any AlertDataStore, notifier: RecordingAlertNotifier, clock: HealthTestClock,
                      settings: AlertSettings = AlertSettings(isEnabled: true)) -> AlertService {
        let defaults = UserDefaults(suiteName: "AlertServiceTests-\(UUID().uuidString)")!
        let settingsStore = AlertSettingsStore(defaults: defaults)
        settingsStore.saveSettings(settings)
        return AlertService(data: store, notifier: notifier, settingsStore: settingsStore,
                            thresholds: { (70, 140) }, now: { clock.now }, timeZone: { TimeZone(identifier: "UTC")! })
    }

    @Test func highReadingNotifiesOnceWithinCooldown() async {
        let store = InMemoryAlertStore()
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(Self.t0)
        let service = make(store: store, notifier: notifier, clock: clock)
        await service.setSessionActive(true)

        await store.add(165, at: clock.now)
        await service.evaluate()
        #expect(notifier.delivered.count == 1)
        let first = notifier.delivered.first
        #expect(first?.kind == .high)
        #expect(first?.title.contains("165") == true)
        #expect(first?.isTimeSensitive == false)
        #expect(first?.threadIdentifier == "lingoscan.alert.high")

        // Segunda lectura alta 5 min después: dentro de los 30 min de silencio entre avisos.
        clock.advance(seconds: 300)
        await store.add(170, at: clock.now)
        await service.evaluate()
        #expect(notifier.delivered.count == 1)

        // Pasados 30 min sigue alta: recordatorio.
        clock.advance(seconds: 25 * 60)
        await store.add(168, at: clock.now)
        await service.evaluate()
        #expect(notifier.delivered.count == 2)
        #expect(await store.logs.filter { $0.hasPrefix("alerta high") }.count == 2)
    }

    @Test func lowIsTimeSensitive() async {
        let store = InMemoryAlertStore()
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(Self.t0)
        let service = make(store: store, notifier: notifier, clock: clock)
        await store.add(62, at: clock.now)
        await service.evaluate()
        #expect(notifier.delivered.map(\.kind) == [.low])
        #expect(notifier.delivered.first?.isTimeSensitive == true)
    }

    @Test func masterSwitchOffSendsNothing() async {
        let store = InMemoryAlertStore()
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(Self.t0)
        let service = make(store: store, notifier: notifier, clock: clock, settings: .default)
        await store.add(200, at: clock.now)
        #expect(await service.evaluate().isEmpty)
        #expect(notifier.delivered.isEmpty)
    }

    @Test func withoutPermissionLogsButDoesNotNotify() async {
        let store = InMemoryAlertStore()
        let notifier = RecordingAlertNotifier()
        notifier.setPermission(.denied)
        let clock = HealthTestClock(Self.t0)
        let service = make(store: store, notifier: notifier, clock: clock)
        await store.add(200, at: clock.now)
        #expect(await service.evaluate().map(\.kind) == [.high])
        #expect(notifier.delivered.isEmpty)
        #expect(await store.logs.contains { $0.contains("sin permiso") })
    }

    @Test func eachReadingReschedulesNoData() async throws {
        let store = InMemoryAlertStore()
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(Self.t0)
        let service = make(store: store, notifier: notifier, clock: clock)
        await service.setSessionActive(true)
        await store.add(110, at: clock.now)
        await service.evaluate()
        let first = try #require(notifier.scheduled.last)
        #expect(first.0.id == AlertService.pendingNoDataID)
        #expect(first.1 == Self.t0.addingTimeInterval(20 * 60 + 1))

        clock.advance(seconds: 60)
        await store.add(112, at: clock.now)
        await service.evaluate()
        #expect(notifier.cancelled.contains(AlertService.pendingNoDataID))
        #expect(notifier.scheduled.last?.1 == Self.t0.addingTimeInterval(21 * 60 + 1))

        // iOS entregó el programado; al evaluar después no se repite como inmediato.
        clock.advance(seconds: 25 * 60)
        await service.evaluate()
        #expect(notifier.delivered.isEmpty)
    }

    @Test func endedSessionCancelsNoData() async {
        let store = InMemoryAlertStore()
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(Self.t0)
        let service = make(store: store, notifier: notifier, clock: clock)
        await service.setSessionActive(true)
        await store.add(110, at: clock.now)
        await service.evaluate()
        await service.handle(.ended(reason: .expired))
        #expect(notifier.cancelled.contains(AlertService.pendingNoDataID))
    }

    @Test func sqliteStoreFeedsEligibleReadingsAndLogsAlertCategory() async throws {
        let sqlite = try HealthFixtures.makeStore()
        let session = HealthFixtures.session()
        try await sqlite.upsertSession(session)
        let readings = (100...105).map { HealthFixtures.reading(session, lifeCount: $0, value: 180) }
        _ = try await sqlite.insertReadings(readings)
        let last = try #require(readings.last)
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(last.measuredAt.date.addingTimeInterval(30))
        let service = make(store: sqlite, notifier: notifier, clock: clock)
        await service.evaluate()
        #expect(notifier.delivered.map(\.kind) == [.high])
        let logs = try await sqlite.recentLogEvents(limit: 10)
        #expect(logs.contains { $0.category == "alert" && $0.message.contains("alerta high") })
    }

    @Test func composerFormatsSlopeAndTip() {
        let composer = AlertMessageComposer(timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "es_CO"))
        let event = AlertEvent(kind: .high, at: UTCInstant(epochSeconds: 1_800_000_000), value: 165,
                               slopePerMinute: 2.4, since: UTCInstant(epochSeconds: 1_799_999_400))
        let n = composer.notification(for: event, low: 70, high: 140, tip: "Consejo")
        #expect(n.title.contains("165 mg/dL"))
        #expect(n.body.contains("2,4 mg/dL"))
        #expect(n.body.hasSuffix("\nConsejo"))
    }

    @Test func editingHelpersForSettingsControls() {
        var s = AlertSettings(isEnabled: true)
        s.quietHoursEnabled = true
        #expect(s.quietHours == .night)
        s[enabled: .risingFast] = false
        #expect(!s.isEnabled(.risingFast))
        s.sharedCooldownMinutes = 60
        #expect(s.cooldown(for: .high) == 60 && s.cooldown(for: .fallingFast) == 60 && s.cooldown(for: .noData) == 60)
        s.sharedCooldownMinutes = 15
        #expect(s.cooldown(for: .low) == 15 && s.cooldown(for: .noData) == 60)
        s.quietHoursEnabled = false
        #expect(s.quietHours == nil)
    }

    @Test @MainActor func controllerPersistsEditedSettings() {
        let defaults = UserDefaults(suiteName: "AlertsController-\(UUID().uuidString)")!
        let store = AlertSettingsStore(defaults: defaults)
        let service = AlertService(data: InMemoryAlertStore(), notifier: RecordingAlertNotifier(), settingsStore: store,
                                   thresholds: { (70, 140) })
        let controller = AlertsController(service: service, store: store)
        controller.settings.quietHoursEnabled = true
        controller.settings.rateThreshold = 3.2
        #expect(store.loadSettings().quietHours == .night)
        #expect(store.loadSettings().rateThreshold == 3.0)
        #expect(controller.settings.rateThreshold == 3.0)
    }

    @Test func legacyAlarmSettingsAreInherited() throws {
        let defaults = UserDefaults(suiteName: "AlertLegacy-\(UUID().uuidString)")!
        defaults.set(Data(#"{"lowMgdl":70,"highMgdl":180,"noDataMinutes":30,"lowEnabled":true,"highEnabled":false,"noDataEnabled":true}"#.utf8),
                     forKey: AlertSettingsStore.legacyAlarmKey)
        let settings = AlertSettingsStore(defaults: defaults).loadSettings()
        #expect(settings.isEnabled && !settings.isEnabled(.high) && settings.isEnabled(.low))
        #expect(settings.noDataAfterMinutes == 30)
    }
}
