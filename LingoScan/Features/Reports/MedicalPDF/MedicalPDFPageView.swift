import SwiftUI

/// Una página Carta (612 × 792 pt) del PDF: encabezado, las piezas que le tocan, pie y, con datos sintéticos, la marca
/// de agua (T-34). Siempre en modo claro y con letra de tamaño fijo, sea cual sea la apariencia o el Dynamic Type.
struct MedicalPDFPageView: View {
    let document: MedicalReportDocument
    let slices: [MedicalPageSlice]
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            MedicalPDFPalette.paper
            if document.isSynthetic { watermark }
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: MedicalPDFLayout.spacing) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in content(slice) }
                }
                .frame(width: MedicalPDFLayout.contentWidth, height: MedicalPDFLayout.contentHeight, alignment: .topLeading)
                .padding(.top, 12)
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, MedicalPDFLayout.margin)
        }
        .frame(width: MedicalPDFLayout.pageSize.width, height: MedicalPDFLayout.pageSize.height, alignment: .topLeading)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
        .foregroundStyle(MedicalPDFPalette.ink)
        .font(.system(size: 9))
    }

    // MARK: Piezas

    @ViewBuilder
    private func content(_ slice: MedicalPageSlice) -> some View {
        switch (slice.id, slice.kind) {
        case ("summary", _):
            MedicalPDFSummaryView(document: document)
        case ("agp", _):
            MedicalPDFAGPView(document: document)
        case ("daily", .rows(let rows, let isContinuation)):
            MedicalPDFDailyGridView(document: document, range: rows, isContinuation: isContinuation)
        case ("method", .rows(let rows, let isContinuation)):
            MedicalPDFMethodView(paragraphs: document.methodNotes, range: rows, isContinuation: isContinuation)
        case (let id, .rows(let rows, let isContinuation)):
            if let table = document.table(id: id) {
                MedicalPDFTableView(table: table, range: rows, isContinuation: isContinuation)
            }
        default:
            EmptyView()
        }
    }

    // MARK: Encabezado y pie

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: "Lingclose")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MedicalPDFPalette.accent)
            Text(verbatim: headerDetail)
                .font(.system(size: 9))
                .foregroundStyle(MedicalPDFPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(width: MedicalPDFLayout.contentWidth, height: MedicalPDFLayout.headerHeight, alignment: .bottomLeading)
        .padding(.bottom, 0)
        .overlay(alignment: .bottom) { Rectangle().fill(MedicalPDFPalette.hairline).frame(height: 0.8) }
    }

    private var headerDetail: String {
        let parts = [document.patientName, document.periodText].filter { !$0.isEmpty }
        return "· " + parts.joined(separator: " · ")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: MedicalReportStrings.page(pageNumber, of: pageCount) + "  ·  "
                 + MedicalReportStrings.generated(document.generatedAtText))
                .font(.system(size: 7.5, weight: .medium))
            Text(verbatim: MedicalReportStrings.disclaimer)
                .font(.system(size: 7.5))
        }
        .foregroundStyle(MedicalPDFPalette.secondary)
        .frame(width: MedicalPDFLayout.contentWidth, height: MedicalPDFLayout.footerHeight, alignment: .topLeading)
        .overlay(alignment: .top) { Rectangle().fill(MedicalPDFPalette.hairline).frame(height: 0.8) }
    }

    private var watermark: some View {
        Text(verbatim: MedicalReportStrings.watermark)
            .font(.system(size: 66, weight: .heavy))
            .foregroundStyle(MedicalPDFPalette.band(.low).opacity(0.10))
            .rotationEffect(.degrees(-35))
            .fixedSize()
            .position(x: MedicalPDFLayout.pageSize.width / 2, y: MedicalPDFLayout.pageSize.height / 2)
            .allowsHitTesting(false)
    }
}
