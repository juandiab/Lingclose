import Foundation

/// Grupos de la pantalla Ajustes, en el orden en que importan al usuario (T-31, D-34): primero lo que cambia cómo se
/// leen los datos, luego el aspecto, las conexiones con otros servicios, lo avanzado y "Acerca de".
enum SettingsGroup: String, CaseIterable, Identifiable, Sendable {
    case readings
    case personalization
    case medicalReport
    case connections
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .readings: String(localized: "settings.group.readings", defaultValue: "Lecturas")
        case .personalization: String(localized: "settings.group.personalization", defaultValue: "Personalización")
        case .medicalReport: String(localized: "settings.group.medicalReport", defaultValue: "Reporte médico")
        case .connections: String(localized: "settings.group.connections", defaultValue: "Conexiones")
        case .advanced: String(localized: "settings.group.advanced", defaultValue: "Avanzado")
        case .about: String(localized: "settings.about", defaultValue: "Acerca de")
        }
    }

    /// Una o dos frases en lenguaje llano: qué hace el grupo y qué pasa si se cambia.
    var footer: String {
        switch self {
        case .readings:
            String(localized: "settings.group.readings.footer",
                   defaultValue: "El rango decide qué parte de la curva se ve como \"en rango\" y cuándo avisan las alertas. Solo orienta la lectura; no es un objetivo médico.")
        case .personalization:
            String(localized: "settings.group.personalization.footer",
                   defaultValue: "Cambia solo el aspecto de Lingclose, nunca tus datos. El idioma se aplica al volver a abrir la app.")
        case .medicalReport:
            String(localized: "settings.group.medicalReport.footer",
                   defaultValue: "El nombre aparece solo en el PDF para el médico que generas desde Reportes › Compartir. Se guarda en este iPhone y nunca sale en los datos compartidos ni en el análisis con IA.")
        case .connections:
            String(localized: "settings.group.connections.footer",
                   defaultValue: "Apple Salud guarda tus lecturas y aporta tus entrenamientos. El asistente con IA es opcional: usa tu propia clave y el proveedor te cobra cada consulta.")
        case .advanced:
            String(localized: "settings.group.advanced.footer",
                   defaultValue: "Solo hace falta si algo falla con el sensor. Cambiar la identidad del sensor puede impedir que se conecte.")
        case .about:
            String(localized: "settings.about.footer",
                   defaultValue: "Lingclose es un proyecto personal de bienestar, no un dispositivo médico.")
        }
    }
}
