import Foundation
import LingoCore

/// Reporte que se entrega a la hoja de análisis, con los eventos del período (nombres de comidas, T-33);
/// identificable para `sheet(item:)`.
struct ReportsAnalysisSheetItem: Identifiable {
    let id = UUID()
    let bundle: ReportBundle
    let events: [DiaryEvent]
}
