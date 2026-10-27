import LingoCore

extension ArchiveUploadState {
    /// Estado de iCloud en texto. Solo `icloudUploaded` dice "disponible"; nunca se presume la subida.
    var title: String {
        switch self {
        case .localWritten: String(localized: "data.upload.local", defaultValue: "Archivo creado, pendiente de subir a iCloud")
        case .icloudUploading: String(localized: "data.upload.uploading", defaultValue: "Subiendo a iCloud")
        case .icloudUploaded: String(localized: "data.upload.uploaded", defaultValue: "Disponible en iCloud")
        case .icloudError(let message): String(localized: "data.upload.error", defaultValue: "Error de iCloud: \(message)")
        case .unknown: String(localized: "data.upload.unknown", defaultValue: "Archivo creado; la carpeta no informa de iCloud")
        }
    }

    var systemImage: String {
        switch self {
        case .localWritten, .unknown: "doc"
        case .icloudUploading: "icloud.and.arrow.up"
        case .icloudUploaded: "checkmark.icloud"
        case .icloudError: "exclamationmark.icloud"
        }
    }
}
