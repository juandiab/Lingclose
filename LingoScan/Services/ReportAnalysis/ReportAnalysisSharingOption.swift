/// Cada bloque de contexto opcional que el usuario puede dejar ver a la IA al analizar un reporte (T-33). Todos
/// apagados por defecto; se guardan en `LLMSettingsStore`.
enum ReportAnalysisSharingOption: String, CaseIterable, Identifiable, Sendable {
    /// Nombre y nutrientes de cada comida del reporte.
    case meals
    /// Sueño por noche y pasos por día, de Apple Salud.
    case sleepActivity
    /// Edad, sexo, peso, altura e IMC, de Apple Salud.
    case profile

    var id: String { rawValue }

    /// Clave de `UserDefaults` del interruptor.
    var defaultsKey: String {
        switch self {
        case .meals: "lingoscan.llm.analysis.share_meals.v1"
        case .sleepActivity: "lingoscan.llm.analysis.share_sleep_activity.v1"
        case .profile: "lingoscan.llm.analysis.share_profile.v1"
        }
    }

    /// `true` si encenderlo necesita permiso de lectura de Apple Salud.
    var readsHealth: Bool { self != .meals }
}
