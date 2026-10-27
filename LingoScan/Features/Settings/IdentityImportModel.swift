import Foundation
import Observation

/// Importación de la identidad de app (Ajustes y `onOpenURL`). Solo muestra etiqueta y
/// familias servidas; nunca el contenido del JSON.
@MainActor
@Observable
final class IdentityImportModel {
    private(set) var summaries: [IdentitySummary] = []
    private(set) var hasLingoSigningKeys = false
    private(set) var isImporting = false
    /// Resultado de la última importación, para un `alert`.
    var message: IdentityImportMessage?

    var isShowingMessage: Bool {
        get { message != nil }
        set { if !newValue { message = nil } }
    }

    private let credentials: CredentialStore

    init(credentials: CredentialStore) {
        self.credentials = credentials
    }

    func refresh() async {
        summaries = await credentials.installedSummaries()
        hasLingoSigningKeys = await credentials.hasLingoSigningKeys()
    }

    /// `fileImporter` o archivo recibido por AirDrop (`onOpenURL`).
    func importIdentity(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            try await credentials.importIdentity(from: url)
            await refresh()
            let labels = summaries.map(\.label).joined(separator: ", ")
            message = IdentityImportMessage(
                title: String(localized: "identity.import.ok.title", defaultValue: "Identidad importada"),
                text: String(localized: "identity.import.ok.text", defaultValue: "Guardada en el llavero de este iPhone: \(labels).")
            )
        } catch let error as CredentialImportError {
            message = IdentityImportMessage(
                title: String(localized: "identity.import.failed.title", defaultValue: "No se importó la identidad"),
                text: error.description
            )
        } catch {
            message = IdentityImportMessage(
                title: String(localized: "identity.import.failed.title", defaultValue: "No se importó la identidad"),
                text: String(localized: "identity.import.failed.generic", defaultValue: "No se pudo guardar en el llavero.")
            )
        }
    }

    func reportPickerFailure() {
        message = IdentityImportMessage(
            title: String(localized: "identity.import.failed.title", defaultValue: "No se importó la identidad"),
            text: String(localized: "identity.import.picker", defaultValue: "No se pudo abrir el archivo elegido.")
        )
    }
}
