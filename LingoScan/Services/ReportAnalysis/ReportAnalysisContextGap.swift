/// Bloque de contexto encendido que quedó vacío en este período (T-33). Nunca hace fallar el análisis.
enum ReportAnalysisContextGap: String, Sendable, Hashable, CaseIterable, Identifiable {
    case meals, sleep, steps, profile

    var id: String { rawValue }
}
