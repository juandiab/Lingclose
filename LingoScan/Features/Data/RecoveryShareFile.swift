import Foundation

/// Estado del archivo que se ofrece en "Compartir última copia".
enum RecoveryShareFile: Equatable, Sendable {
    /// Aún no hay copia exportada.
    case none
    /// El ledger recuerda una copia, pero el archivo ya no está en disco.
    case missing
    /// Copia lista para compartir (un temporal, legible por `ShareLink`).
    case ready(URL)

    /// Comprueba el archivo con el alcance de seguridad de la carpeta elegida abierto y lo copia a un temporal:
    /// `ShareLink` lee la URL fuera de ese alcance. Síncrono y bloqueante: llamar fuera del hilo principal.
    nonisolated static func prepare(
        record: RecoveryService.ExportRecord?,
        folderKind: RecoveryService.ExportFolder.Kind,
        bookmarks: any FolderBookmarkStoring,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> RecoveryShareFile {
        guard let record else { return .none }
        let scoped: URL? = {
            guard folderKind == .chosen, let data = bookmarks.load() else { return nil }
            return try? FolderBookmark.resolve(data).url
        }()
        let source = record.fileURL
        let copy = { () -> RecoveryShareFile in
            let fm = FileManager.default
            guard fm.fileExists(atPath: source.path) else { return .missing }
            let folder = temporaryDirectory.appending(path: "LingoScanShare", directoryHint: .isDirectory)
            let target = folder.appending(path: record.fileName)
            do {
                try? fm.removeItem(at: folder)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
                return .ready(target)
            } catch {
                return .missing
            }
        }
        if let scoped { return SecurityScopedAccess.run(scoped, copy) }
        return copy()
    }
}
