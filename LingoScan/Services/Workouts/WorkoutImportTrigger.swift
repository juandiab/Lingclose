import Foundation
import Observation

/// Importación automática de entrenamientos: en primer plano al abrir la app y cuando Salud avisa; en segundo plano,
/// la entrega de Salud despierta la app, se importa y se confirma el aviso. También expone el estado para Ajustes y
/// la importación manual ("Importar ahora").
@MainActor
@Observable
final class WorkoutImportTrigger {
    /// Instancia activa (una por proceso); `TodayView` la avisa al volver a primer plano.
    private(set) static var current: WorkoutImportTrigger?

    private(set) var isImporting = false
    private(set) var status = WorkoutImportStatus(lastImportAt: nil, lastReport: nil, totalImported: 0)
    private(set) var didFail = false

    @ObservationIgnored private let importer: WorkoutImporter
    @ObservationIgnored private let source: any WorkoutSource
    @ObservationIgnored private var observeTask: Task<Void, Never>?

    init(importer: WorkoutImporter, source: any WorkoutSource) {
        self.importer = importer
        self.source = source
    }

    isolated deinit {
        observeTask?.cancel()
    }

    /// Registra esta instancia como la activa y empieza a escuchar a Salud (también en relanzamientos en segundo plano).
    func install() {
        Self.current = self
        guard observeTask == nil else { return }
        let changes = source.observeNewWorkouts()
        observeTask = Task { [weak self] in
            for await notice in changes {
                await self?.run()
                notice.acknowledge()
            }
        }
        Task { await refreshStatus() }
    }

    /// Llamar con `scenePhase == .active`.
    func sceneDidBecomeActive() {
        Task { await run() }
    }

    /// Importación manual: pide permiso de lectura (si ya se decidió, iOS no vuelve a preguntar) e importa.
    @discardableResult
    func importNow() async -> WorkoutImportReport? {
        try? await source.requestReadAuthorization()
        return await run()
    }

    func refreshStatus() async {
        status = await importer.status()
    }

    @discardableResult
    private func run() async -> WorkoutImportReport? {
        isImporting = true
        defer { isImporting = false }
        do {
            let report = try await importer.importNew()
            didFail = false
            await refreshStatus()
            return report
        } catch {
            didFail = true
            return nil
        }
    }
}
