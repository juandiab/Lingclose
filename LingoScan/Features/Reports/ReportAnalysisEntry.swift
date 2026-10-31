import LingoCore
import SwiftUI

/// Punto de entrada del análisis con IA (T-27d). Reportes muestra "Analizar con IA" solo si el entorno trae uno,
/// y al tocarlo presenta `makeSheet(bundle, events)` en una hoja. Los eventos del período solo se usan si el usuario
/// enciende "Comidas con nombre" (T-33). Quien lo implementa decide qué envía y cómo.
struct ReportAnalysisEntry: Sendable {
    let makeSheet: @MainActor (ReportBundle, [DiaryEvent]) -> AnyView
}

extension EnvironmentValues {
    /// `nil` (por defecto): sin botón de análisis.
    @Entry var reportAnalysisEntry: ReportAnalysisEntry?
}
