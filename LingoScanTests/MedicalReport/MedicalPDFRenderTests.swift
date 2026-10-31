import Foundation
import PDFKit
import Testing
import UIKit
@testable import LingoScan

/// T-34: el PDF real, con 14 días de datos inventados: páginas, tamaño Carta y texto extraíble. Si existe la variable de
/// entorno `LINGO_PDF_SAMPLE_OUT` (con el prefijo `TEST_RUNNER_` al lanzar `xcodebuild`), escribe ahí el PDF de ejemplo
/// y, junto a él, una PNG por página.
@MainActor
struct MedicalPDFRenderTests {
    @Test func fourteenDayReportRendersLetterPagesWithExtractableText() async throws {
        let document = MedicalReportBuilder.build(await MedicalReportFixtures.input())
        let data = try await MedicalPDFRenderer.render(document)
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount > 1)
        #expect(pdf.pageCount == MedicalPDFRenderer.pages(for: document).count)
        for index in 0..<pdf.pageCount {
            let bounds = try #require(pdf.page(at: index)).bounds(for: .mediaBox)
            #expect(bounds.size == CGSize(width: 612, height: 792), "página \(index + 1): \(bounds)")
        }
        let text = try #require(pdf.string)
        #expect(text.contains(MedicalReportFixtures.testName), "El nombre debe estar en el texto del PDF")
        #expect(text.contains("GMI"))
        #expect(text.contains("Abbott Lingo") && text.contains("FreeStyle Libre 3"))
        #expect(text.contains(MedicalReportStrings.watermark), "Marca de agua con datos sintéticos")
        #expect(text.contains(MedicalReportStrings.disclaimer))
        // Encabezado y pie en cada página.
        for index in 0..<pdf.pageCount {
            let page = try #require(pdf.page(at: index)).string ?? ""
            #expect(page.contains("Lingclose") && page.contains(MedicalReportFixtures.testName), "encabezado, página \(index + 1)")
            #expect(page.contains(MedicalReportStrings.page(index + 1, of: pdf.pageCount)), "pie, página \(index + 1)")
        }
        try exportSampleIfRequested(pdf: pdf, data: data)
    }

    @Test func realDataHasNoWatermarkAndAnEmptyNameLeavesTheHeaderClean() async throws {
        let document = MedicalReportBuilder.build(await MedicalReportFixtures.input(name: "", isSynthetic: false))
        let data = try await MedicalPDFRenderer.render(document)
        let text = try #require(PDFDocument(data: data)?.string)
        #expect(!text.contains(MedicalReportStrings.watermark))
        #expect(text.contains(MedicalReportStrings.noName))
    }

    @Test func longReportSplitsTablesOverPagesWithoutLosingRows() async throws {
        let document = MedicalReportBuilder.build(await MedicalReportFixtures.input(days: 31))
        let pages = MedicalPDFRenderer.pages(for: document)
        let mealRows = pages.flatMap { $0 }.compactMap { slice -> Int? in
            guard slice.id == "meals", case .rows(let range, _) = slice.kind else { return nil }
            return range.count
        }
        #expect(mealRows.reduce(0, +) == document.meals?.rows.count)
        #expect(mealRows.count > 1, "31 días de comidas no caben en un solo tramo")
        let data = try await MedicalPDFRenderer.render(document)
        #expect(PDFDocument(data: data)?.pageCount == pages.count)
    }

    // MARK: Ejemplo para revisión visual

    private func exportSampleIfRequested(pdf: PDFDocument, data: Data) throws {
        guard let path = ProcessInfo.processInfo.environment["LINGO_PDF_SAMPLE_OUT"], !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        let base = url.deletingPathExtension()
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let size = CGSize(width: 612 * 2, height: 792 * 2)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: 2, y: -2)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
            let png = try #require(image.pngData())
            try png.write(to: URL(fileURLWithPath: base.path + "-p\(index + 1).png"), options: .atomic)
        }
    }
}
