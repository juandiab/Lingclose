import Foundation
import LingoCore

/// Resultado de "Exportar ahora" tal como lo muestra la tarjeta Archivo.
struct ArchiveExportSummary: Equatable, Sendable {
    let packageName: String
    let readings: Int
    let events: Int
    let verified: Bool
    let failure: String?
    /// Cuándo terminó la exportación (para la confirmación visible).
    var exportedAt = Date()
    /// Paquetes antiguos que la retención borró en esta exportación.
    var removedByRetention = 0
}

/// Una línea del resumen de importación (`ImportSummary` o rechazo).
struct ArchiveImportLine: Equatable, Identifiable, Sendable {
    enum Outcome: Equatable, Sendable {
        case imported(producer: String, new: Int, updated: Int, identical: Int, conflicts: Int)
        case skipped(producer: String)
        case rejected(name: String, reason: String)
    }

    let id: Int
    let outcome: Outcome

    init(id: Int, outcome: Outcome) {
        self.id = id
        self.outcome = outcome
    }

    init(id: Int, _ outcome: PackageImportOutcome) {
        switch outcome {
        case .imported(let s):
            self.init(id: id, outcome: .imported(
                producer: s.producerAppID, new: s.newTotal, updated: s.updatedTotal, identical: s.identicalTotal,
                conflicts: s.conflictsRecorded))
        case .skipped(let s):
            self.init(id: id, outcome: .skipped(producer: s.producerAppID))
        case .rejected(let name, let reason, _):
            self.init(id: id, outcome: .rejected(name: name, reason: reason))
        }
    }
}

/// Costura de la pantalla Datos con `ArchiveService`; las pruebas inyectan un doble en memoria.
@MainActor
protocol ArchiveManaging: AnyObject {
    var destination: ArchiveDestination { get }
    var packages: [ArchivePackageStatus] { get }
    var isWorking: Bool { get }
    var lastError: String? { get }
    func refresh() async
    func chooseFolder(_ url: URL) async
    func forgetFolder() async
    func exportNow() async -> ArchiveExportSummary?
    func importPackages(from url: URL) async -> [ArchiveImportLine]
}

/// `ArchiveService` real. Las propiedades se reenvían: al ser el servicio `@Observable`, la vista las sigue.
@MainActor
final class LiveArchiveManager: ArchiveManaging {
    private let service: ArchiveService

    init(service: ArchiveService) {
        self.service = service
    }

    var destination: ArchiveDestination { service.destination }
    var packages: [ArchivePackageStatus] { service.packages }
    var isWorking: Bool { service.isWorking }
    var lastError: String? { service.lastError }

    func refresh() async { await service.refresh() }
    func chooseFolder(_ url: URL) async { await service.chooseFolder(url) }
    func forgetFolder() async { await service.forgetFolder() }

    func exportNow() async -> ArchiveExportSummary? {
        guard let result = await service.exportNow() else { return nil }
        return ArchiveExportSummary(
            packageName: result.url.lastPathComponent, readings: result.manifest.counts.readings,
            events: result.manifest.counts.events, verified: result.verified, failure: result.verificationFailure,
            removedByRetention: result.removedByRetention.count)
    }

    func importPackages(from url: URL) async -> [ArchiveImportLine] {
        await service.importPackages(from: url).enumerated().map { ArchiveImportLine(id: $0.offset, $0.element) }
    }
}
