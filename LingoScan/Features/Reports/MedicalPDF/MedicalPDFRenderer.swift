import CoreGraphics
import Foundation
import SwiftUI

/// Dibuja el `MedicalReportDocument` en un PDF Carta vectorial (T-34): `ImageRenderer.render` sobre un `CGContext` PDF,
/// una página por vista. Texto y trazados quedan como vectores y el texto es seleccionable y buscable.
@MainActor
enum MedicalPDFRenderer {
    enum RenderError: Error {
        case contextUnavailable
    }

    /// Reparte el documento en páginas con las medidas de `MedicalPDFLayout`.
    static func pages(for document: MedicalReportDocument) -> [[MedicalPageSlice]] {
        MedicalReportPaginator.paginate(
            MedicalReportFlow.items(for: document), contentHeight: Double(MedicalPDFLayout.contentHeight),
            spacing: Double(MedicalPDFLayout.spacing))
    }

    /// Genera los bytes del PDF. `progress` recibe (página terminada, total) y se cede el hilo entre páginas para que
    /// la hoja pueda animar su indicador.
    static func render(_ document: MedicalReportDocument,
                       progress: (@MainActor (Int, Int) -> Void)? = nil) async throws -> Data {
        let pages = pages(for: document)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: MedicalPDFLayout.pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: MedicalReportStrings.documentTitle,
            kCGPDFContextCreator: "Lingclose",
        ]
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else {
            throw RenderError.contextUnavailable
        }
        for (index, slices) in pages.enumerated() {
            try Task.checkCancellation()
            let view = MedicalPDFPageView(document: document, slices: slices, pageNumber: index + 1, pageCount: pages.count)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(MedicalPDFLayout.pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
            progress?(index + 1, pages.count)
            await Task.yield()
        }
        context.closePDF()
        return data as Data
    }
}
