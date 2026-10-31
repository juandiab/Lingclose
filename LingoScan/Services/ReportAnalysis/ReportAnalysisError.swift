import Foundation

/// Fallos del análisis de reportes que no vienen del proveedor (esos son `LLMError`).
enum ReportAnalysisError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    case notConfigured
    case alreadyRunning
    case rejected(term: String)

    var description: String {
        switch self {
        case .notConfigured:
            String(localized: "reports.analysis.error.notConfigured",
                   defaultValue: "No hay asistente configurado. Elige proveedor, clave y modelo en Ajustes → Asistente de comidas.")
        case .alreadyRunning:
            String(localized: "reports.analysis.error.alreadyRunning", defaultValue: "Ya hay un análisis en curso.")
        case .rejected(let term):
            String(localized: "reports.analysis.error.rejected",
                   defaultValue: "La respuesta se descartó porque mencionaba temas médicos (\(term)). Esta guía solo habla de hábitos.")
        }
    }

    var errorDescription: String? { description }
}
