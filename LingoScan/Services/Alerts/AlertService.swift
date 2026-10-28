import Foundation
import LingoCore

/// Alertas de glucosa (T-24). Se engancha al flujo de estados del `SensorSessionCoordinator`: cada lectura en vivo
/// guardada en SQLite produce un `.streaming(last:)` nuevo, y el coordinador lo emite también cuando iOS despierta la
/// app en segundo plano por BLE (`bluetooth-central`). Con cada uno se cargan de SQLite las lecturas elegibles
/// recientes, se evalúa con `AlertEvaluator` (puro), se guarda el `AlertState` y se notifica.
///
/// "Sin datos" no puede depender de que llegue algo (precisamente no llega nada): tras cada evaluación se programa
/// una notificación para `última lectura + plazo`, que reemplaza a la anterior; iOS la entrega aunque la app esté
/// suspendida. Al evaluar de nuevo, si ya pasó su hora se da por entregada para no repetirla.
actor AlertService {
    static let pendingNoDataID = "lingoscan.alert.noData.pending"
    /// Lecturas para alta, baja y pendiente.
    static let sampleWindowSeconds: Int64 = 20 * 60
    /// Hasta dónde se busca la última lectura para "sin datos".
    static let lookbackSeconds: Int64 = 6 * 3600

    private let data: any AlertDataStore
    private let notifier: any AlertNotifying
    private let settingsStore: AlertSettingsStore
    private let thresholds: @Sendable () -> (low: Int, high: Int)
    private let now: @Sendable () -> Date
    private let timeZone: @Sendable () -> TimeZone
    private var sessionActive = false
    private var observing: Task<Void, Never>?

    init(
        data: any AlertDataStore,
        notifier: any AlertNotifying,
        settingsStore: AlertSettingsStore,
        thresholds: @escaping @Sendable () -> (low: Int, high: Int),
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.data = data
        self.notifier = notifier
        self.settingsStore = settingsStore
        self.thresholds = thresholds
        self.now = now
        self.timeZone = timeZone
    }

    // MARK: - Enganche

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
        case .streaming(let last):
            sessionActive = true
            // Solo las lecturas en vivo disparan una evaluación; el relleno ya está en SQLite y entra en la siguiente.
            if last.origin == .live { await evaluate() }
        case .stale, .reconnecting:
            sessionActive = true
            await evaluate()
        case .warmingUp, .activating, .pairing:
            sessionActive = false
        case .noSensor, .identified, .incompatible, .readyToActivate, .ended, .authenticationFailed, .paused:
            sessionActive = false
            await cancelPendingNoData()
        }
    }

    /// Para tests y para cuando la sesión ya está viva antes de suscribirse.
    func setSessionActive(_ active: Bool) { sessionActive = active }

    // MARK: - Evaluación

    /// Evalúa con las lecturas de SQLite. Devuelve los avisos disparados (también si no se pudieron notificar).
    @discardableResult
    func evaluate() async -> [AlertEvent] {
        let settings = settingsStore.loadSettings()
        guard settings.isEnabled else {
            await cancelPendingNoData()
            return []
        }
        let date = now()
        let instant = UTCInstant(date)
        let recent: [BasicStats.Sample]
        do {
            recent = try await data.alertSamples(in: instant.adding(seconds: -Self.lookbackSeconds)...instant)
        } catch {
            await data.logAlert(.warning, "lecturas no leídas: \(public: String(describing: type(of: error)))")
            return []
        }
        let lastReadingAt = recent.last?.measuredAt
        let window = recent.filter { instant.epochSeconds - $0.measuredAt.epochSeconds <= Self.sampleWindowSeconds }
        let (low, high) = thresholds()
        let zone = timeZone()

        var state = settingsStore.loadState()
        if let pending = settingsStore.pendingNoDataAt, pending <= instant {
            // iOS ya mostró la notificación "sin datos" programada.
            state = state.assumingDelivered(.noData, at: pending, since: lastReadingAt)
            settingsStore.pendingNoDataAt = nil
        }
        let result = AlertEvaluator.evaluate(
            samples: window, now: instant, low: low, high: high, settings: settings, state: state,
            sessionActive: sessionActive, lastReadingAt: lastReadingAt, timeZone: zone)
        settingsStore.saveState(result.state)

        let composer = AlertMessageComposer(timeZone: zone)
        let authorized = await notifier.authorization() == .authorized
        for event in result.alerts {
            if event.kind == .noData { await cancelPendingNoData() }
            await log(event)
            guard authorized else {
                await data.logAlert(.info, "alerta \(public: event.kind.rawValue) sin notificar: sin permiso")
                continue
            }
            do {
                try await notifier.deliver(composer.notification(for: event, low: low, high: high))
            } catch {
                await data.logAlert(.warning, "alerta \(public: event.kind.rawValue) no notificada: \(public: String(describing: type(of: error)))")
            }
        }
        await armNoData(settings: settings, state: result.state, lastReadingAt: lastReadingAt, now: instant,
                        composer: composer, authorized: authorized)
        return result.alerts
    }

    /// Tras cambiar ajustes en la app.
    func settingsDidChange() async {
        await evaluate()
    }

    // MARK: - Permiso y prueba

    func permission() async -> AlertPermission { await notifier.authorization() }

    func requestPermission() async -> Bool { await notifier.requestAuthorization() }

    /// Notificación de ejemplo inmediata. Devuelve `false` sin permiso o si iOS la rechaza.
    func sendTest() async -> Bool {
        guard await notifier.authorization() == .authorized else { return false }
        do {
            try await notifier.deliver(AlertMessageComposer(timeZone: timeZone()).testNotification(at: now()))
            await data.logAlert(.info, "notificación de prueba enviada")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Sin datos programado

    private func armNoData(settings: AlertSettings, state: AlertState, lastReadingAt: UTCInstant?, now: UTCInstant,
                           composer: AlertMessageComposer, authorized: Bool) async {
        await cancelPendingNoData()
        guard authorized, settings.isEnabled(.noData), sessionActive, let lastReadingAt else { return }
        let deadline = lastReadingAt.adding(seconds: Int64(settings.noDataAfterMinutes) * 60 + 1)
        guard deadline > now else { return }
        // El silencio entre avisos y las horas de silencio se aplican a la hora de entrega.
        if let fired = state.lastFired[.noData],
           deadline.epochSeconds - fired.epochSeconds < Int64(settings.cooldown(for: .noData)) * 60 { return }
        if let quiet = settings.quietHours,
           quiet.contains(minuteOfDay: AlertEvaluator.localMinute(of: deadline, in: composer.timeZone)) { return }
        let event = AlertEvent(kind: .noData, at: deadline, value: nil, slopePerMinute: nil, since: lastReadingAt)
        let base = composer.notification(for: event, low: 0, high: 0)
        let pending = AlertNotification(id: Self.pendingNoDataID, kind: .noData, title: base.title, body: base.body,
                                        isTimeSensitive: base.isTimeSensitive)
        do {
            try await notifier.schedule(pending, at: deadline.date)
            settingsStore.pendingNoDataAt = deadline
        } catch {
            await data.logAlert(.warning, "aviso sin datos no programado: \(public: String(describing: type(of: error)))")
        }
    }

    private func cancelPendingNoData() async {
        guard settingsStore.pendingNoDataAt != nil else { return }
        await notifier.cancelPending(ids: [Self.pendingNoDataID])
        settingsStore.pendingNoDataAt = nil
    }

    private func log(_ event: AlertEvent) async {
        let slope = event.slopePerMinute.map { $0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX"))) } ?? "-"
        if let value = event.value {
            await data.logAlert(.info, "alerta \(public: event.kind.rawValue): \(value) mg/dL, pendiente \(public: slope)/min")
        } else {
            await data.logAlert(.info, "alerta \(public: event.kind.rawValue): sin lecturas desde \(event.since ?? event.at)")
        }
    }
}
