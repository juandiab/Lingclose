import SwiftUI

extension EnvironmentValues {
    /// Fuentes de Salud del análisis con IA (T-33). Por defecto las sintéticas: solo la app real inyecta `.live`, así
    /// que `#Preview` nunca pide permisos de Salud.
    @Entry var reportAnalysisHealth: ReportAnalysisHealthSources = .preview
}
