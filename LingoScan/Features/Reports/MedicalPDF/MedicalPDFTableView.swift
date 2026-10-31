import SwiftUI

/// Un tramo de una tabla del reporte: título (o "continuación"), cabecera de columnas y las filas `range` (T-34).
/// Cada fila mide `table.rowHeight` y recorta su texto a `lineLimit` líneas: nada se desborda ni se parte.
struct MedicalPDFTableView: View {
    let table: MedicalTable
    let range: Range<Int>
    let isContinuation: Bool

    var body: some View {
        let widths = MedicalPDFLayout.columnWidths(table.columns)
        VStack(alignment: .leading, spacing: 0) {
            if isContinuation {
                MedicalPDFSectionTitle(
                    title: table.title + " " + MedicalReportStrings.continued, subtitle: nil,
                    height: MedicalPDFLayout.continuationTitleHeight(title: table.title))
            } else {
                MedicalPDFSectionTitle(
                    title: table.title, subtitle: table.subtitle, height: MedicalPDFLayout.titleHeight(for: table))
            }
            header(widths)
            ForEach(range, id: \.self) { index in
                row(table.rows[index], index: index, widths: widths)
            }
        }
        .frame(width: MedicalPDFLayout.contentWidth, alignment: .topLeading)
    }

    private func header(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(table.columns.indices, id: \.self) { column in
                Text(verbatim: table.columns[column].title)
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(MedicalPDFPalette.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(textAlignment(table.columns[column].alignment))
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 3)
                    .frame(width: widths[column], height: MedicalPDFLayout.headerRowHeight,
                           alignment: frameAlignment(table.columns[column].alignment, bottom: true))
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(MedicalPDFPalette.accent.opacity(0.55)).frame(height: 0.8) }
    }

    private func row(_ cells: [String], index: Int, widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(table.columns.indices, id: \.self) { column in
                Text(verbatim: column < cells.count ? cells[column] : "")
                    .font(.system(size: MedicalPDFLayout.cellSize))
                    .monospacedDigit()
                    .foregroundStyle(MedicalPDFPalette.ink)
                    .lineLimit(table.lineLimit)
                    .multilineTextAlignment(textAlignment(table.columns[column].alignment))
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 3)
                    .frame(width: widths[column], height: table.rowHeight,
                           alignment: frameAlignment(table.columns[column].alignment, bottom: false))
            }
        }
        .background(index.isMultiple(of: 2) ? Color.clear : MedicalPDFPalette.zebra)
    }

    private func textAlignment(_ alignment: MedicalColumnAlignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func frameAlignment(_ alignment: MedicalColumnAlignment, bottom: Bool) -> Alignment {
        switch (alignment, bottom) {
        case (.leading, true): .bottomLeading
        case (.center, true): .bottom
        case (.trailing, true): .bottomTrailing
        case (.leading, false): .leading
        case (.center, false): .center
        case (.trailing, false): .trailing
        }
    }
}
