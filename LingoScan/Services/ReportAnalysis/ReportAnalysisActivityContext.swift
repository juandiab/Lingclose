/// Actividad diaria de Apple Salud para el análisis (T-33): pasos por día local. Los entrenamientos del Watch ya van
/// en el snapshot como sesiones de ejercicio (hora y duración); `workout_links` no guarda su tipo, kcal ni
/// frecuencia cardíaca, así que no se añaden aquí.
struct ReportAnalysisActivityContext: Sendable, Hashable, Codable {
    var dailySteps: [DailySteps]

    enum CodingKeys: String, CodingKey {
        case dailySteps = "daily_steps"
    }
}
