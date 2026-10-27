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
    private(set) var importLines: [ArchiveImportLine] = []
    var isConfirmingFillGaps = false

    @ObservationIgnored let archive: any ArchiveManaging
    @ObservationIgnored private let healthController: any HealthControlling
    @ObservationIgnored private let eventLog: any EventLogReading

    /// Cuántas copias recientes se listan.
    static let visiblePackages = 5
    /// Cuántos errores recientes se resumen.
    static let visibleErrors = 8

    init(archive: any ArchiveManaging, health: any HealthControlling, eventLog: any EventLogReading) {
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
        exportSummary = await archive.exportNow()
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
}
