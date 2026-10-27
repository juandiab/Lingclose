import Foundation
import Observation

/// Estado de la pantalla de recuperación. La frase solo pasa por aquí de camino al actor (memoria).
@MainActor
@Observable
final class RecoveryViewModel {
    private(set) var status: RecoveryService.Status = .empty
    private(set) var importedSession: RecoveryService.ImportedSessionDetail?
    private(set) var lastReport: RecoveryService.ImportReport?
    private(set) var message: String?
    private(set) var isWorking = false
    var passphrase = ""
    var includeMaterial = false

    let service: RecoveryService
    let connector: (any RecoveryActiveSensorConnecting)?

    init(context: RecoveryContext) {
        service = context.service
        connector = context.connector
    }

    /// Sigue los cambios del servicio (exportaciones de transición incluidas) mientras la vista vive.
    func observe() async {
        await refreshImported()
        for await status in await service.updates() {
            self.status = status
            await refreshImported()
        }
    }

    func usePassphrase() async {
        await run {
            try await self.service.setPassphrase(self.passphrase)
            self.passphrase = ""
            return String(localized: "recovery.passphrase.saved", defaultValue: "Frase guardada solo en memoria hasta cerrar la app")
        }
    }

    func forgetPassphrase() async {
        await service.forgetPassphrase()
    }

    func exportNow() async {
        await run {
            let record = try await self.service.exportNow(includeMaterial: self.includeMaterial)
            self.includeMaterial = false
            return String(localized: "recovery.export.done", defaultValue: "Exportado \(record.fileName)")
        }
    }

    func importFile(_ url: URL) async {
        await run {
            let report = try await self.service.importFile(at: url)
            self.lastReport = report
            return String(localized: "recovery.import.done",
                          defaultValue: "Importado: \(report.changedSessions.count) sesión(es) actualizadas, \(report.conflictCount) conflicto(s), \(report.historicalCount) intento(s) histórico(s)")
        }
    }

    func report(_ error: any Error) {
        message = String(describing: error)
    }

    private func refreshImported() async {
        importedSession = await service.latestImportedSession()
    }

    private func run(_ work: @escaping () async throws -> String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            message = try await work()
        } catch {
            message = String(describing: error)
        }
        await refreshImported()
    }
}
