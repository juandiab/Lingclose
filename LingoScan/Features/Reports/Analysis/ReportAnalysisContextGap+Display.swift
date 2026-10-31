import Foundation

/// Línea discreta para un bloque encendido que quedó vacío (T-33).
extension ReportAnalysisContextGap {
    var message: String {
        switch self {
        case .meals:
            String(localized: "reports.analysis.gap.meals", defaultValue: "No hay comidas con nombre ni nutrientes en este período: van solo las cifras.")
        case .sleep:
            String(localized: "reports.analysis.gap.sleep", defaultValue: "Apple Salud no devolvió datos de sueño en este período.")
        case .steps:
            String(localized: "reports.analysis.gap.steps", defaultValue: "Apple Salud no devolvió pasos en este período.")
        case .profile:
            String(localized: "reports.analysis.gap.profile", defaultValue: "Apple Salud no devolvió datos de perfil ni de composición corporal.")
        }
    }
}
