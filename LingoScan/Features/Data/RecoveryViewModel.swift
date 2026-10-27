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
    var passphraseConfirmation = ""
    /// Confirmación obligatoria de que la frase ya está guardada fuera del teléfono.
    var passphraseSavedElsewhere = false
    /// Guardar la frase en el Llavero del iPhone (solo este dispositivo) para no pedirla en cada arranque.
    var rememberPassphrase = false
    var includeMaterial = false

    let service: RecoveryService
    let connector: (any RecoveryActiveSensorConnecting)?

    init(context: RecoveryContext) {
        service = context.service
        connector = context.connector
    }

    /// Sigue los cambios del servicio (exportaciones de transición incluidas) mientras la vista vive.
    func observe() async {
        await service.start()
        await refreshImported()
        for await status in await service.updates() {
            self.status = status
            await refreshImported()
        }
    }

    /// `true` solo si el último `usePassphrase()` terminó sin error (la hoja se cierra con esto).
    private(set) var passphraseAccepted = false

    func usePassphrase() async {
        passphraseAccepted = false
        await run {
            let remember = self.rememberPassphrase
            try await self.service.setPassphrase(self.passphrase, remember: remember)
            self.passphrase = ""
            self.passphraseConfirmation = ""
            self.passphraseSavedElsewhere = false
            self.passphraseAccepted = true
            return remember
                ? String(localized: "recovery.passphrase.remembered", defaultValue: "Frase guardada en el Llavero de este iPhone")
                : String(localized: "recovery.passphrase.saved", defaultValue: "Frase guardada solo en memoria hasta cerrar la app")
        }
    }

    /// Vacía lo escrito en la hoja sin tocar la frase ya registrada en el servicio.
    func resetPassphraseEntry() {
        passphrase = ""
        passphraseConfirmation = ""
        passphraseSavedElsewhere = false
        rememberPassphrase = false
        passphraseAccepted = false
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

    func exportForAstra() async {
        await run {
            let record = try await self.service.exportCurrentForAstra(includeMaterial: self.includeMaterial)
            self.includeMaterial = false
            return "Exportado para Astra: \(record.fileName)"
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
