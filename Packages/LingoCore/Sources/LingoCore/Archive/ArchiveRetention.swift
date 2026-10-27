import Foundation

/// Retención de paquetes propios (contrato §3.3): los últimos 7 más uno por mes (el más reciente de cada mes).
/// Nunca incluye paquetes de otro `producer_tag` ni carpetas `.partial`.
public enum ArchiveRetention {
    public static let keepLast = 7

    /// Nombres de carpeta a borrar entre `names` (todos los de la carpeta destino).
    public static func foldersToDelete(among names: [String], producerTag: String, keepLast: Int = keepLast) -> [String] {
        let own = names.compactMap { n -> (String, ArchivePackageName)? in
            guard let p = ArchivePackageName(parsing: n), p.producerTag == producerTag else { return nil }
            return (n, p)
        }.sorted { ($0.1.createdAt, $0.0) > ($1.1.createdAt, $1.0) }  // más reciente primero
        var keep = Set(own.prefix(keepLast).map(\.0))
        var seenMonths = Set<String>()
        for (n, p) in own {
            let month = String(p.createdAt.rfc3339.prefix(7))
            if seenMonths.insert(month).inserted { keep.insert(n) }
        }
        return own.map(\.0).filter { !keep.contains($0) }.sorted()
    }

    /// Aplica la retención en `directory` y devuelve lo que borró.
    @discardableResult
    public static func apply(in directory: URL, producerTag: String, keepLast: Int = keepLast) throws -> [String] {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: directory.path)
        let doomed = foldersToDelete(among: names, producerTag: producerTag, keepLast: keepLast)
        for n in doomed { try fm.removeItem(at: directory.appending(path: n, directoryHint: .isDirectory)) }
        return doomed
    }
}

/// Estado de un paquete en iCloud (contrato §3.2), a partir de las claves de recurso del sistema.
public enum ArchiveUploadState: Sendable, Hashable {
    /// Paso 5 completado; el sistema no informa más.
    case localWritten
    case icloudUploading
    case icloudUploaded
    case icloudError(String)
    /// La carpeta no es ubicua o el sistema no informa.
    case unknown

    public var code: String {
        switch self {
        case .localWritten: "local_written"
        case .icloudUploading: "icloud_uploading"
        case .icloudUploaded: "icloud_uploaded"
        case .icloudError: "icloud_error"
        case .unknown: "unknown"
        }
    }

    /// `NSURLUbiquitousItemIsUploadedKey` / `…IsUploadingKey` / `…UploadingErrorKey` de un archivo.
    public static func from(isUbiquitous: Bool, isUploaded: Bool?, isUploading: Bool?, errorDescription: String?) -> ArchiveUploadState {
        guard isUbiquitous else { return .unknown }
        if let errorDescription { return .icloudError(errorDescription) }
        if isUploading == true { return .icloudUploading }
        if isUploaded == true { return .icloudUploaded }
        if isUploaded == nil && isUploading == nil { return .unknown }
        return .localWritten
    }

    /// Estado de una carpeta a partir del de cada archivo: error > subiendo > local > subido solo si todos lo están.
    public static func aggregate(_ states: [ArchiveUploadState]) -> ArchiveUploadState {
        guard !states.isEmpty else { return .unknown }
        for s in states { if case .icloudError = s { return s } }
        if states.contains(.icloudUploading) { return .icloudUploading }
        if states.contains(.unknown) { return .unknown }
        if states.contains(.localWritten) { return .localWritten }
        return .icloudUploaded
    }

    /// "Respaldado" solo con `icloud_uploaded` (la UI no puede decir más, contrato §3.2).
    public var isBackedUp: Bool { self == .icloudUploaded }
}
