/// Secciones opcionales del reporte para el médico (T-34). Las de glucosa (resumen, AGP, perfiles diarios, franjas y
/// comparación semanal) siempre van.
struct MedicalReportOptions: Sendable, Hashable {
    var meals = true
    var sleepActivity = true
    var exercise = true
    var bodyComposition = true
    var notes = true

    /// Todo encendido, como abre la hoja.
    static let all = MedicalReportOptions()
}
