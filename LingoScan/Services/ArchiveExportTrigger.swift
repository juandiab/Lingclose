import Foundation
import LingoCore

/// Copia diaria `.lingoscan` en proceso, independiente de `BGAppRefreshTask` (que iOS puede no ejecutar en días).
///
/// La app vive casi siempre en segundo plano por el enlace BLE, así que basta con mirar de vez en cuando:
/// - al volver a primer plano (`scenePhase == .active`, desde `RootTabView`);
/// - a los 2 min del arranque (`initialDelay`), para los relanzamientos por BLE en segundo plano que iOS mata antes
///   de la hora, y luego cada hora mientras el proceso viva (`clock.sleep`, inyectable).
///
/// `ArchiveService.exportIfDue()` decide si toca (último paquete propio de más de 20 h) y no duplica una exportación
/// en curso. Si una exportación falla en segundo plano (p. ej. la carpeta del bookmark no es accesible sin primer
/// plano), `exportNow` ya lo registra; los ticks no lo reintentan hasta pasada `retryBackoff`, y el siguiente `.active`
/// sí lo reintenta.
@MainActor
final class ArchiveExportTrigger {
    /// Instancia activa (una por proceso); `RootTabView` la avisa al volver a primer plano.
    private(set) static var current: ArchiveExportTrigger?

    static let defaultInitialDelay: Duration = .seconds(120)
    static let defaultTickInterval: Duration = .seconds(3600)
    static let defaultRetryBackoff: TimeInterval = 3600

    enum Reason: Sendable { case tick, active }

    private let service: ArchiveService
    private let store: SQLiteStore
    private let clock: any SessionClock
    private let initialDelay: Duration
    private let tickInterval: Duration
    private let retryBackoff: TimeInterval
    private var loopTask: Task<Void, Never>?
    private var activeTask: Task<Void, Never>?
    private var isChecking = false
    /// Tras un fallo, los ticks no reintentan antes de esta fecha.
    private var retryNotBefore: Date?
    /// Comprobaciones terminadas (incluidas las que no exportan). Diagnóstico y tests.
    private(set) var completedChecks = 0

    init(
        service: ArchiveService,
        store: SQLiteStore,
        clock: any SessionClock = SystemSessionClock(),
        initialDelay: Duration = ArchiveExportTrigger.defaultInitialDelay,
        tickInterval: Duration = ArchiveExportTrigger.defaultTickInterval,
        retryBackoff: TimeInterval = ArchiveExportTrigger.defaultRetryBackoff
    ) {
        self.service = service
        self.store = store
        self.clock = clock
        self.initialDelay = initialDelay
        self.tickInterval = tickInterval
        self.retryBackoff = retryBackoff
    }

    isolated deinit {
        loopTask?.cancel()
        activeTask?.cancel()
    }

    /// Registra esta instancia como la activa del proceso: una comprobación a los `initialDelay` del arranque y
    /// después el bucle horario.
    func install() {
        Self.current = self
        guard loopTask == nil else { return }
        let clock = clock
        let initialDelay = initialDelay
        let tickInterval = tickInterval
        loopTask = Task { [weak self] in
            var delay = initialDelay
            while !Task.isCancelled {
                do { try await clock.sleep(for: delay) } catch { return }
                guard let self else { return }
                await self.check(.tick)
                delay = tickInterval
            }
        }
    }

    /// Detiene el bucle y deja de ser la instancia activa (tests).
    func stop() {
        loopTask?.cancel()
        loopTask = nil
        if Self.current === self { Self.current = nil }
    }

    /// Llamar con `scenePhase == .active`: comprueba (y exporta si toca) sin esperar al siguiente tick.
    @discardableResult
    func sceneDidBecomeActive() -> Task<Void, Never> {
        let task = Task { await check(.active) }
        activeTask = task
        return task
    }

    /// Una comprobación: si la copia diaria venció, registra una línea y llama a `exportIfDue()`.
    func check(_ reason: Reason) async {
        defer { completedChecks += 1 }
        guard !isChecking, !service.isWorking else { return }
        if reason == .tick, let retryNotBefore, clock.now < retryNotBefore { return }
        isChecking = true
        defer { isChecking = false }

        let lastExport = await service.lastOwnExportDate()
        guard service.destination.url != nil else { return }
        let dueSince = lastExport?.addingTimeInterval(service.exportInterval)
        if let dueSince, clock.now < dueSince { return }

        let since = dueSince.map { UTCInstant($0).rfc3339 } ?? "siempre (sin copia propia)"
        try? await store.logEvent(.info, category: "archive", "copia diaria vencida desde \(public: since); exportando")
        let ok = await service.exportIfDue()
        retryNotBefore = ok ? nil : clock.now.addingTimeInterval(retryBackoff)
    }
}
