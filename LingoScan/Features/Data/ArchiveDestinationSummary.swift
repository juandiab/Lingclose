import Foundation

/// Dónde acaban los paquetes y las copias de recuperación, en una frase. La usan Datos y Recuperación para
/// que ambas pantallas digan exactamente lo mismo.
enum ArchiveDestinationSummary: Equatable, Sendable {
    case chosenFolder(name: String)
    case appICloudContainer
    case appDocuments
    case none

    init(_ destination: ArchiveDestination) {
        switch destination {
        case .userFolder(let url): self = .chosenFolder(name: url.lastPathComponent)
        case .appICloudContainer: self = .appICloudContainer
        case .unavailable: self = .none
        }
    }

    init(kind: RecoveryService.ExportFolder.Kind, folderName: String) {
        switch kind {
        case .chosen, .fixed: self = .chosenFolder(name: folderName)
        case .appICloudContainer: self = .appICloudContainer
        case .documents, .unavailable: self = .appDocuments
        }
    }

    var title: String {
        switch self {
        case .chosenFolder(let name):
            String(localized: "data.archive.dest.folder", defaultValue: "Carpeta elegida: \(name)")
        case .appICloudContainer:
            String(localized: "data.archive.dest.app", defaultValue: "Carpeta de la app en iCloud Drive (Archivos → LingoScan)")
        case .appDocuments:
            String(localized: "data.archive.dest.documents", defaultValue: "Documentos de la app (Archivos → En mi iPhone → LingoScan)")
        case .none:
            String(localized: "data.archive.dest.none", defaultValue: "Sin destino")
        }
    }

    var systemImage: String {
        switch self {
        case .chosenFolder: "folder"
        case .appICloudContainer: "icloud"
        case .appDocuments: "iphone"
        case .none: "exclamationmark.triangle"
        }
    }
}
