import CoreGraphics

/// Medidas fijas del PDF para el médico (T-34), en puntos de PDF. Tamaño Carta; los márgenes y las alturas de
/// título, cabecera y fila salen de aquí tanto para repartir páginas como para dibujarlas.
enum MedicalPDFLayout {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 36
    static var contentWidth: CGFloat { pageSize.width - 2 * margin }
    /// Banda del encabezado (marca, nombre y período) y del pie (página, fecha y aviso).
    static let headerHeight: CGFloat = 46
    static let footerHeight: CGFloat = 40
    static var contentHeight: CGFloat { pageSize.height - headerHeight - footerHeight - 24 }
    static let spacing: CGFloat = 14

    // Tablas
    static let tableTitleSize: CGFloat = 12
    static let subtitleSize: CGFloat = 8
    static let cellSize: CGFloat = 8
    static let headerRowHeight: CGFloat = 27
    static let titleGap: CGFloat = 4

    // Rejilla de perfiles diarios
    static let dailyColumns = 7
    static let dailyCellHeight: CGFloat = 78
    static let dailyGap: CGFloat = 6

    // Gráfica AGP
    static let agpChartHeight: CGFloat = 236
    static let agpLegendHeight: CGFloat = 16

    /// Alto del título de una tabla: 12 pt de título más el subtítulo (hasta 3 líneas) y un respiro.
    static func titleHeight(title: String, subtitle: String?) -> CGFloat {
        var height = MedicalTextMetrics.height(of: title, size: tableTitleSize, weight: .semibold, width: contentWidth, maxLines: 1)
        if let subtitle {
            height += 2 + MedicalTextMetrics.height(of: subtitle, size: subtitleSize, width: contentWidth, maxLines: 3)
        }
        return height + titleGap
    }

    /// Título de los tramos siguientes: "título (continuación)", sin subtítulo.
    static func continuationTitleHeight(title: String) -> CGFloat {
        titleHeight(title: title + " " + MedicalReportStrings.continued, subtitle: nil)
    }

    static func titleHeight(for table: MedicalTable) -> CGFloat {
        titleHeight(title: table.title, subtitle: table.subtitle)
    }

    /// Ancho de cada columna de una tabla (proporcional a su peso) para el ancho útil.
    static func columnWidths(_ columns: [MedicalTableColumn], total: CGFloat = contentWidth) -> [CGFloat] {
        let sum = columns.reduce(0) { $0 + $1.weight }
        return columns.map { total * CGFloat($0.weight / sum) }
    }
}
