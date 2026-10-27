import Foundation
import LingoCore
import Observation

/// Estado de la pantalla Datos: Health, archivo `.lingoscan` y errores recientes.
@MainActor
@Observable
final class DataViewModel {
    /// Resumen de la tarjeta Health en una palabra.
    enum HealthStatus: Equatable {
        case notAuthorized
        case paused
        case upToDate
        case pending(Int)
    }

    private(set) var health = HealthSnapshot()
    private(set) var isHealthBusy = false
    /// Resultado del último "Rellenar huecos".
    private(set) var lastFill: HealthDrainSummary?
    private(set) var recentErrors: [EventLogEntry] = []
    private(set) var exportSummary: ArchiveExportSummary?
    /// `true` durante `exportCooldown` tras exportar: evita toques repetidos que crean paquetes de más.
    private(set) var isExportCoolingDown = false
    private(set) var importLines: [ArchiveImportLine] = []
    var isConfirmingFillGaps = false

    @ObservationIgnored let archive: any ArchiveManaging
    @ObservationIgnored private let healthController: any HealthControlling
    @ObservationIgnored private let eventLog: any EventLogReading
    @ObservationIgnored private let exportCooldown: Duration
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?

    /// Cuántas copias recientes se listan.
    static let visiblePackages = 5
    /// Cuántos errores recientes se resumen.
    static let visibleErrors = 8
    /// Cuántos paquetes propios conserva la retención (más uno por mes), el mismo valor que aplica `ArchiveRetention`.
    static let retainedPackages = ArchiveRetention.keepLast
    /// Bloqueo de "Exportar ahora" tras una exportación.
    static let defaultExportCooldown = Duration.seconds(10)

    init(
        archive: any ArchiveManaging, health: any HealthControlling, eventLog: any EventLogReading,
        exportCooldown: Duration = DataViewModel.defaultExportCooldown
    ) {
        self.exportCooldown = exportCooldown
        self.archive = archive
        self.healthController = health
        self.eventLog = eventLog
    }

    // MARK: Derivados

    var healthStatus: HealthStatus {
        if !health.isAuthorized { return .notAuthorized }
        if health.isPaused { return .paused }
        return health.pendingCount > 0 ? .pending(health.pendingCount) : .upToDate
    }

    /// "Rellenar huecos" solo con permiso, fuera de pausa, con pendientes y sin otra operación en curso.
    var canFillGaps: Bool {
        health.isAuthorized && !health.isPaused && health.pendingCount > 0 && !isHealthBusy
    }

    var destination: ArchiveDestination { archive.destination }
    var destinationSummary: ArchiveDestinationSummary { ArchiveDestinationSummary(archive.destination) }
    /// "Exportar ahora" solo con destino, sin operación en curso y fuera del bloqueo posterior a exportar.
    var canExport: Bool { destination.url != nil && !isArchiveWorking && !isExportCoolingDown }
    /// "Usar la carpeta de la app" no tiene sentido si ya es el destino.
    var canUseAppFolder: Bool { !destination.isFallback }
    var isArchiveWorking: Bool { archive.isWorking }
    var archiveError: String? { archive.lastError }
    var visiblePackageList: [ArchivePackageStatus] { Array(archive.packages.prefix(Self.visiblePackages)) }

    // MARK: Carga

    func refresh() async {
        health = await healthController.snapshot()
        await archive.refresh()
        await refreshErrors()
    }

    func refreshErrors() async {
        let entries = (try? await eventLog.recentLogEvents(limit: 200)) ?? []
        recentErrors = Array(entries.filter { $0.level == .warning || $0.level == .error }.prefix(Self.visibleErrors))
    }

    // MARK: Health

    func requestHealthAuthorization() async {
        guard !isHealthBusy else { return }
        isHealthBusy = true
        defer { isHealthBusy = false }
        health = await healthController.requestAuthorization()
    }

    func fillGaps() async {
        guard canFillGaps else { return }
        isHealthBusy = true
        defer { isHealthBusy = false }
        let result = await healthController.fillGaps()
        lastFill = result.summary
        health = result.snapshot
        await refreshErrors()
    }

    // MARK: Archivo

    func exportNow() async {
        guard canExport else { return }
        let summary = await archive.exportNow()
        exportSummary = summary
        if summary != nil { startCooldown() }
        await refreshErrors()
    }

    func chooseFolder(_ url: URL) async {
        await archive.chooseFolder(url)
    }

    func forgetFolder() async {
        await archive.forgetFolder()
    }

    func importPackages(from url: URL) async {
        importLines = await archive.importPackages(from: url)
        await archive.refresh()
        await refreshErrors()
    }

    private func startCooldown() {
        cooldownTask?.cancel()
        isExportCoolingDown = true
        let duration = exportCooldown
        cooldownTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.isExportCoolingDown = false
        }
    }
}
