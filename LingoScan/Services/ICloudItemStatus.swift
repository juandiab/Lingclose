import Foundation
import LingoCore

/// Estado de iCloud de un paquete a partir de lo que informa el sistema (contrato §3.2). Nunca se presume:
/// sin `NSURLUbiquitousItemIsUploadedKey` verdadero en **todos** los archivos del paquete no hay "respaldado".
enum ICloudItemStatus {
    static let keys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
        .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// Estado de un archivo o carpeta suelta.
    static func state(ofItem url: URL) -> ArchiveUploadState {
        guard let values = try? url.resourceValues(forKeys: keys) else { return .unknown }
        return ArchiveUploadState.from(
            isUbiquitous: values.isUbiquitousItem ?? false,
            isUploaded: values.ubiquitousItemIsUploaded,
            isUploading: values.ubiquitousItemIsUploading,
            errorDescription: values.ubiquitousItemUploadingError.map { $0.localizedDescription })
    }

    /// Estado del paquete: combina el de cada archivo (un paquete es una carpeta de archivos independientes).
    static func state(ofPackage url: URL) -> ArchiveUploadState {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        guard !files.isEmpty else { return state(ofItem: url) }
        return ArchiveUploadState.aggregate(files.map(state(ofItem:)))
    }

    /// Pide la descarga de los archivos del paquete que solo están en iCloud y espera hasta `timeout`.
    /// Devuelve `true` si todos están ya en el dispositivo. Para rutas no ubicuas es inmediato.
    static func ensureDownloaded(package url: URL, timeout: Duration = .seconds(30)) async -> Bool {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
        func pending() -> [URL] {
            files.filter { file in
                guard let v = try? file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
                      v.isUbiquitousItem == true else { return false }
                return v.ubiquitousItemDownloadingStatus != .current
            }
        }
        var todo = pending()
        guard !todo.isEmpty else { return true }
        for f in todo { try? fm.startDownloadingUbiquitousItem(at: f) }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            todo = pending()
            if todo.isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return false }
        }
        return pending().isEmpty
    }
}
