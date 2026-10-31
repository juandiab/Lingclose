import Foundation

/// De dónde lee el análisis el contexto de Apple Salud (T-33): sueño y pasos, el perfil de "Sugerir rango"
/// (`HealthProfileReading`, reutilizado tal cual) y la composición corporal de la báscula. Solo lectura.
struct ReportAnalysisHealthSources: Sendable {
    let sleepActivity: any SleepActivityReading
    let profile: any HealthProfileReading
    let bodyComposition: any BodyCompositionReading

    /// App real: Apple Salud.
    static let live = ReportAnalysisHealthSources(
        sleepActivity: HealthKitSleepActivityReader(), profile: HealthKitProfileReader(),
        bodyComposition: HealthKitBodyCompositionReader())

    /// Datos inventados: `#Preview`, `-previewSensorState` y pruebas. Nunca toca Apple Salud.
    static let preview = ReportAnalysisHealthSources(
        sleepActivity: PreviewSleepActivityReader(), profile: PreviewHealthProfileReader(),
        bodyComposition: PreviewBodyCompositionReader())

    /// Pide el permiso de lectura de Salud que necesita un interruptor al encenderse. "Comidas con nombre" no lee
    /// Salud. El perfil (edad, sexo, peso, altura) pide su permiso al leerse (`HealthKitProfileReader`); el valor leído aquí se descarta.
    func requestAccess(for option: ReportAnalysisSharingOption) async {
        switch option {
        case .meals: return
        case .sleepActivity: await sleepActivity.requestAuthorization()
        case .profile:
            _ = try? await profile.readProfile()
            await bodyComposition.requestAuthorization()
        }
    }
}
