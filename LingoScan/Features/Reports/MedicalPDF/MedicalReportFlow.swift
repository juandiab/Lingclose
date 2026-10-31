import CoreGraphics

/// Convierte un `MedicalReportDocument` en la lista de piezas que reparte `MedicalReportPaginator` (T-34). Las
/// secciones opcionales ausentes (apagadas o sin datos) simplemente no generan pieza.
enum MedicalReportFlow {
    /// Alto fijo del resumen de la página 1.
    static let summaryHeight: CGFloat = 560

    static func items(for document: MedicalReportDocument) -> [MedicalFlowItem] {
        var items: [MedicalFlowItem] = [.block(id: "summary", height: summaryHeight, startsPage: false)]
        items.append(.block(id: "agp", height: agpHeight(document), startsPage: true))
        for table in [document.agpTable, document.slots, document.weekly] {
            if let table { items.append(tableItem(table)) }
        }
        if !document.dailyProfiles.isEmpty {
            items.append(.table(
                id: "daily",
                titleHeight: MedicalPDFLayout.titleHeight(title: document.dailyTitle, subtitle: document.dailySubtitle),
                continuationTitleHeight: MedicalPDFLayout.continuationTitleHeight(title: document.dailyTitle),
                headerHeight: 0, rowHeights: dailyRows(document.dailyProfiles.count), startsPage: true))
        }
        for table in [document.meals, document.nights, document.exercise, document.bodySummary, document.bodyByDay, document.notes] {
            if let table { items.append(tableItem(table)) }
        }
        items.append(.table(
            id: "method", titleHeight: MedicalPDFLayout.titleHeight(title: MedicalReportStrings.methodTitle, subtitle: nil),
            continuationTitleHeight: MedicalPDFLayout.continuationTitleHeight(title: MedicalReportStrings.methodTitle),
            headerHeight: 0, rowHeights: document.methodNotes.map(methodRowHeight), startsPage: false))
        return items
    }

    static func tableItem(_ table: MedicalTable) -> MedicalFlowItem {
        .table(id: table.id, titleHeight: MedicalPDFLayout.titleHeight(for: table),
               continuationTitleHeight: MedicalPDFLayout.continuationTitleHeight(title: table.title),
               headerHeight: MedicalPDFLayout.headerRowHeight,
               rowHeights: [Double](repeating: table.rowHeight, count: table.rows.count), startsPage: false)
    }

    /// Título + subtítulo + gráfica + leyenda del AGP.
    static func agpHeight(_ document: MedicalReportDocument) -> Double {
        let title = MedicalPDFLayout.titleHeight(title: MedicalReportStrings.agpTitle, subtitle: MedicalReportStrings.agpSubtitle(document.unitSymbol))
        return Double(title + MedicalPDFLayout.agpChartHeight + 8 + MedicalPDFLayout.agpLegendHeight)
    }

    /// Una fila por cada 7 días.
    static func dailyRows(_ days: Int) -> [Double] {
        let rows = (days + MedicalPDFLayout.dailyColumns - 1) / MedicalPDFLayout.dailyColumns
        return [Double](repeating: Double(MedicalPDFLayout.dailyCellHeight + MedicalPDFLayout.dailyGap), count: rows)
    }

    static let methodTextSize: CGFloat = 8.5

    /// Alto de un párrafo de "Notas y método" (medido) más el espacio hasta el siguiente.
    static func methodRowHeight(_ text: String) -> Double {
        Double(MedicalTextMetrics.height(of: text, size: methodTextSize, width: MedicalPDFLayout.contentWidth) + 7)
    }
}
