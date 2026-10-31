/// Estado de un análisis de reporte por IA guardado en `report_analyses`.
public enum ReportAnalysisStatus: String, Sendable, Hashable, Codable, CaseIterable {
    /// Respuesta válida guardada en `responseJSON`.
    case succeeded
    /// La respuesta llegó pero el validador la rechazó (diagnóstico, fármacos…); `error` dice por qué.
    case rejected
    /// Error de red, proveedor o formato; `error` lo describe.
    case failed
}
