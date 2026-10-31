/// Tabla ya formateada del reporte para el médico (T-34). Todas las filas miden lo mismo (`rowHeight`), así que
/// `MedicalReportPaginator` sabe cuántas caben en una página sin medir texto y ninguna se corta a media página.
struct MedicalTable: Sendable, Hashable {
    /// Alto de fila de una línea y de dos líneas (pt).
    static let singleLineRow: Double = 17
    static let doubleLineRow: Double = 27

    var id: String
    var title: String
    var subtitle: String?
    var columns: [MedicalTableColumn]
    var rows: [[String]]
    var rowHeight: Double = MedicalTable.singleLineRow

    var lineLimit: Int { rowHeight >= Self.doubleLineRow ? 2 : 1 }
    var isEmpty: Bool { rows.isEmpty }
}
