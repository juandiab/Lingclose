import Foundation
import LingoCore
import UserNotifications

/// Permiso de notificaciones visto por la app.
enum AlarmPermission: Sendable, Equatable {
    case notDetermined, denied, authorized
}

/// Notificación local que el servicio quiere mostrar. `delay` en segundos desde ahora.
struct AlarmNotification: Sendable, Equatable {
    let id: String
    let kind: AlarmKind
    let title: String
    let body: String
    /// Solo la alarma baja es `timeSensitive` (atraviesa Focus); alta y "sin datos" respetan Focus.
    let timeSensitive: Bool
    let delay: TimeInterval
}

/// Costura sobre `UNUserNotificationCenter`; los tests inyectan un doble.
protocol NotificationScheduling: Sendable {
    func authorizationStatus() async -> AlarmPermission
    func requestAuthorization() async throws -> Bool
    func schedule(_ notification: AlarmNotification) async throws
    func cancel(ids: [String]) async
}

struct SystemNotificationScheduler: NotificationScheduling {
    func authorizationStatus() async -> AlarmPermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .timeSensitive])
    }

    func schedule(_ notification: AlarmNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.interruptionLevel = notification.timeSensitive ? .timeSensitive : .active
        content.threadIdentifier = "lingoscan.alarms"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, notification.delay), repeats: false)
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    func cancel(ids: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

/// Alarmas alta, baja y "sin datos". Consume los estados del coordinador; la decisión la toma
/// `AlarmPolicy` (pura). Informativo, no médico.
actor AlarmService {
    static let noDataID = "lingoscan.alarm.nodata"

    private let settingsStore: AlarmSettingsStore
    private let scheduler: any NotificationScheduling
    private let now: @Sendable () -> Date
    private var alarmState = AlarmState()
    private var lastSampleAt: UTCInstant?
    private var observing: Task<Void, Never>?

    init(settings: AlarmSettingsStore, scheduler: any NotificationScheduling = SystemNotificationScheduler(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.settingsStore = settings
        self.scheduler = scheduler
        self.now = now
    }

    func permission() async -> AlarmPermission { await scheduler.authorizationStatus() }

    func requestPermission() async -> Bool {
        (try? await scheduler.requestAuthorization()) ?? false
    }

    /// Se suscribe a los estados del coordinador. Idempotente.
    func observe(_ states: AsyncStream<SessionState>) {
        observing?.cancel()
        observing = Task { [weak self] in
            for await state in states {
                await self?.handle(state)
            }
        }
    }

    func handle(_ state: SessionState) async {
        switch state {
        case .paused:
            alarmState = alarmState.paused(true)
            await scheduler.cancel(ids: [Self.noDataID])
        case .streaming(let last):
            alarmState = alarmState.paused(false)
            guard last.eligible, last.origin == .live, let value = last.valueMgdl else { return }
            await ingest(AlarmSample(valueMgdl: value, measuredAt: last.measuredAt, lifeCount: last.lifeCount))
        case .warmingUp, .stale, .reconnecting, .activating, .pairing:
            alarmState = alarmState.paused(false)
        case .noSensor, .identified, .incompatible, .readyToActivate, .ended, .authenticationFailed:
            // Sin sesión viva no hay "sin datos" pendiente.
            alarmState = alarmState.paused(false)
            await scheduler.cancel(ids: [Self.noDataID])
        }
    }

    /// Lectura completa: solo pasa si es elegible, en vivo y no sintética (vía `HealthExportable`).
    func ingest(reading: GlucoseReading) async {
        guard let sample = AlarmSample(reading: reading) else { return }
        await ingest(sample)
    }

    func ingest(_ sample: AlarmSample) async {
        // Las tramas repetidas del mismo minuto no vuelven a evaluarse.
        if let last = lastSampleAt, sample.measuredAt <= last { return }
        lastSampleAt = sample.measuredAt
        let settings = settingsStore.load()
        let instant = UTCInstant(now())
        let result = AlarmPolicy.evaluate(sample: sample, now: instant, settings: settings, state: alarmState)
        alarmState = result.state
        if case .fire(let kind, let value) = result.decision, await isAuthorized() {
            try? await scheduler.schedule(notification(kind, value: value, settings: settings, delay: 1))
        }
        await armNoData(settings: settings)
    }

    /// Tras editar umbrales o interruptores en Ajustes.
    func settingsDidChange() async {
        await armNoData(settings: settingsStore.load())
    }

    /// "Sin datos": una notificación con `timeInterval`, reemplazada por cada lectura válida.
    private func armNoData(settings: AlarmSettings) async {
        await scheduler.cancel(ids: [Self.noDataID])
        guard settings.noDataEnabled, !alarmState.isPaused, let last = alarmState.lastValid, await isAuthorized() else { return }
        let deadline = AlarmPolicy.noDataDeadline(lastValid: last, settings: settings)
        let delay = max(1, TimeInterval(deadline.epochSeconds) - now().timeIntervalSince1970)
        try? await scheduler.schedule(notification(.noData, value: nil, settings: settings, delay: delay))
    }

    private func isAuthorized() async -> Bool { await scheduler.authorizationStatus() == .authorized }

    private func notification(_ kind: AlarmKind, value: Int?, settings: AlarmSettings, delay: TimeInterval) -> AlarmNotification {
        let note = String(localized: "alarm.note", defaultValue: "Informativo; no es un dispositivo médico.")
        switch kind {
        case .low:
            return AlarmNotification(
                id: "lingoscan.alarm.low", kind: kind,
                title: String(localized: "alarm.low.title", defaultValue: "Glucosa baja"),
                body: String(localized: "alarm.low.body", defaultValue: "\(value ?? 0) mg/dL, por debajo de \(settings.lowMgdl). \(note)"),
                timeSensitive: true, delay: delay)
        case .high:
            return AlarmNotification(
                id: "lingoscan.alarm.high", kind: kind,
                title: String(localized: "alarm.high.title", defaultValue: "Glucosa alta"),
                body: String(localized: "alarm.high.body", defaultValue: "\(value ?? 0) mg/dL, por encima de \(settings.highMgdl). \(note)"),
                timeSensitive: false, delay: delay)
        case .noData:
            return AlarmNotification(
                id: Self.noDataID, kind: kind,
                title: String(localized: "alarm.nodata.title", defaultValue: "Sin datos del sensor"),
                body: String(localized: "alarm.nodata.body", defaultValue: "No llegan lecturas desde hace \(settings.noDataMinutes) min. \(note)"),
                timeSensitive: false, delay: delay)
        }
    }
}
