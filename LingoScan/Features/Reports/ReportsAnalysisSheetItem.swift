import Foundation
import LingoCore

/// Reporte que se entrega a la hoja de análisis; identificable para `sheet(item:)`.
struct ReportsAnalysisSheetItem: Identifiable {
    let id = UUID()
    let bundle: ReportBundle
}
