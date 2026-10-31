/// Pieza del flujo del reporte que `MedicalReportPaginator` reparte en páginas (T-34). Todas las alturas son fijas y
/// salen de `MedicalPDFLayout`; así el reparto es puro y la vista dibuja exactamente lo que se midió.
enum MedicalFlowItem: Sendable, Hashable {
    /// Bloque indivisible (resumen, gráfica AGP). `startsPage`: siempre empieza página.
    case block(id: String, height: Double, startsPage: Bool)
    /// Título + cabecera de columnas y filas que se reparten entre páginas sin partir ninguna. El primer tramo lleva
    /// `titleHeight` (título y subtítulo); los siguientes, `continuationTitleHeight` (solo "título (continuación)").
    /// La cabecera de columnas (`headerHeight`) se repite en cada tramo; `headerHeight == 0` es una rejilla sin cabecera.
    case table(id: String, titleHeight: Double, continuationTitleHeight: Double, headerHeight: Double,
               rowHeights: [Double], startsPage: Bool)

    var id: String {
        switch self {
        case .block(let id, _, _), .table(let id, _, _, _, _, _): id
        }
    }
}
