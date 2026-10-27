import Foundation
import LingoCore
import os

/// Lo que la tarjeta de Health muestra.
struct HealthSnapshot: Sendable, Equatable {
    var isAuthorized = false
    /// Sujetos (lecturas y comidas con gramos) sin estado `written`, incluidos los retenidos por el traspaso.
    var pendingCount = 0
    /// Modo "en pausa" (traspaso de rol): no se escribe nada en Health.
    var isPaused = false
    var lastError: String?
    /// Último "Rellenar huecos" lanzado desde esta pantalla.
    var lastAttempt: Date?
}

struct HealthFillResult: Sendable, Equatable {
    var summary: HealthDrainSummary
    var snapshot: HealthSnapshot
}

/// Costura de la pantalla Datos con el exportador a Health; las pruebas inyectan un doble.
protocol HealthControlling: Sendable {
    func snapshot() async -> HealthSnapshot
    /// Muestra la hoja de permisos de Health y devuelve el estado resultante.
    func requestAuthorization() async -> HealthSnapshot
    /// "Rellenar huecos en Health": ignora el traspaso y escribe todos los pendientes (acción explícita).
    func fillGaps() async -> HealthFillResult
}

/// Interruptor que el exportador consulta en cada drenado para saber si "Rellenar huecos" está en curso.
final class FillGapsSwitch: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var isOn: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

/// `HealthExporter` real. Solo "Rellenar huecos" enciende `fillGaps`, y solo mientras dura ese drenado.
final class LiveHealthController: HealthControlling {
    static let lastAttemptKey = "com.otalvaro.lingoscan.health.lastFillAttempt"

    private let exporter: HealthExporter
    private let fillGapsSwitch: FillGapsSwitch
    private let isPaused: @Sendable () async -> Bool
    private let now: @Sendable () -> Date
    nonisolated(unsafe) private let defaults: UserDefaults

    init(
        exporter: HealthExporter,
        fillGapsSwitch: FillGapsSwitch,
        isPaused: @escaping @Sendable () async -> Bool,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.exporter = exporter
        self.fillGapsSwitch = fillGapsSwitch
        self.isPaused = isPaused
        self.defaults = defaults
        self.now = now
    }

    func snapshot() async -> HealthSnapshot {
        await exporter.refreshAuthorization()
        await exporter.refreshPending()
        return await makeSnapshot()
    }

    func requestAuthorization() async -> HealthSnapshot {
        await exporter.requestAuthorization()
        await exporter.refreshPending()
        return await makeSnapshot()
    }

    func fillGaps() async -> HealthFillResult {
        guard !(await isPaused()) else {
            return HealthFillResult(summary: HealthDrainSummary(paused: true), snapshot: await makeSnapshot())
        }
        fillGapsSwitch.isOn = true
        let summary = await exporter.drain(force: true)
        fillGapsSwitch.isOn = false
        defaults.set(now(), forKey: Self.lastAttemptKey)
        return HealthFillResult(summary: summary, snapshot: await makeSnapshot())
    }

    private func makeSnapshot() async -> HealthSnapshot {
        HealthSnapshot(
            isAuthorized: await exporter.isAuthorized,
            pendingCount: await exporter.pendingCount,
            isPaused: await isPaused(),
            lastError: await exporter.lastError,
            lastAttempt: defaults.object(forKey: Self.lastAttemptKey) as? Date)
    }
}
