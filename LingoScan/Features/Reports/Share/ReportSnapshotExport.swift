import CoreTransferable
import Foundation
import LingoCore
import UniformTypeIdentifiers

/// `ReportSnapshot` como fichero `.json` temporal (claves ordenadas, sin texto libre, ids ni seriales).
/// La instantánea se calcula al compartir, no al dibujar la pantalla.
struct ReportSnapshotExport: Transferable {
    let bundle: ReportBundle

    /// "lingclose-reporte-2026-10-18_2026-10-31.json".
    var fileName: String {
        let first = bundle.summary.days.first?.day.date ?? "inicio"
        let last = bundle.summary.days.last?.day.date ?? "fin"
        return "lingclose-reporte-\(first)_\(last).json"
    }

    func jsonData() throws -> Data {
        try bundle.snapshot.jsonData()
    }

    /// Escribe el JSON en el directorio temporal y devuelve su URL.
    func writeTemporaryFile() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: fileName)
        try jsonData().write(to: url, options: .atomic)
        return url
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            SentTransferredFile(try export.writeTemporaryFile())
        }
    }
}
