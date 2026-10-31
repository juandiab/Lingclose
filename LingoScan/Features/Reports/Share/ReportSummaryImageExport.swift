import CoreTransferable
import Foundation
import ImageIO
import LingoCore
import SwiftUI
import UniformTypeIdentifiers

/// Resumen del período como PNG (`ImageRenderer` sobre `ReportSummaryShareView`), generado al compartir.
struct ReportSummaryImageExport: Transferable {
    let bundle: ReportBundle
    let isSynthetic: Bool

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { export in
            try await export.pngData()
        }
        .suggestedFileName("lingclose-resumen.png")
    }

    @MainActor
    func pngData() throws -> Data {
        let renderer = ImageRenderer(content: ReportSummaryShareView(bundle: bundle, isSynthetic: isSynthetic))
        renderer.scale = 3
        guard let image = renderer.cgImage else { throw ReportExportError.imageRenderingFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ReportExportError.pngEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ReportExportError.pngEncodingFailed }
        return data as Data
    }
}
