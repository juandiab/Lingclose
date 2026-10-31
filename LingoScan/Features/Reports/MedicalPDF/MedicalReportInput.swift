import Foundation
import LingoCore

/// Todo lo que `MedicalReportBuilder` necesita, ya leído (T-34). Nada aquí toca HealthKit ni la red: el modelo de vista
/// lee Apple Salud al pulsar "Generar PDF" y entrega los valores; las pruebas inyectan datos inventados.
struct MedicalReportInput: Sendable {
    var bundle: ReportBundle
    var events: [DiaryEvent]
    /// Nutrición por `eventID` de las comidas del período.
    var nutrition: [String: MealNutritionRecord] = [:]
    var profile: HealthProfile = .empty
    /// Último valor de cada medida corporal y tendencias (lo que ya usa el análisis con IA).
    var body: BodyComposition = .empty
    /// Todas las mediciones de la báscula dentro del período.
    var bodySeries: BodyMeasurementSeries = .empty
    var sleep: [SleepNight] = []
    var steps: [DailySteps] = []
    var options: MedicalReportOptions = .all
    var patientName = ""
    var isSynthetic = false
    var generatedAt: Date = .now
    var unit: MedicalGlucoseUnit = .mgdl
    var locale: Locale = .current
}
