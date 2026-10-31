import Foundation

/// De dónde lee el análisis el contexto de Apple Salud (T-33): sueño y pasos, el perfil de "Sugerir rango"
/// (`HealthProfileReading`, reutilizado tal cual) y la composición corporal de la báscula. Solo lectura.
struct ReportAnalysisHealthSources: Sendable {
    let sleepActivity: any SleepActivityReading
    let profile: any HealthProfileReading
    let bodyComposition: any BodyCompositionReading
    /// Perfil del reporte en PDF para el médico (T-34): lo mismo que `profile` más fecha de nacimiento y grupo
    /// sanguíneo. Aparte de `profile` para que los permisos de "Sugerir rango" y del análisis no cambien.
    let medicalProfile: any HealthProfileReading

    init(sleepActivity: any SleepActivityReading, profile: any HealthProfileReading,
         bodyComposition: any BodyCompositionReading,
         medicalProfile: any HealthProfileReading = PreviewHealthProfileReader.medicalPreview) {
        self.sleepActivity = sleepActivity
        self.profile = profile
        self.bodyComposition = bodyComposition
        self.medicalProfile = medicalProfile
    }

    /// App real: Apple Salud.
    static let live = ReportAnalysisHealthSources(
        sleepActivity: HealthKitSleepActivityReader(), profile: HealthKitProfileReader(),
        bodyComposition: HealthKitBodyCompositionReader(),
        medicalProfile: HealthKitProfileReader(includesBloodType: true))

    /// Datos inventados: `#Preview`, `-previewSensorState` y pruebas. Nunca toca Apple Salud.
    static let preview = ReportAnalysisHealthSources(
        sleepActivity: PreviewSleepActivityReader(), profile: PreviewHealthProfileReader(),
        bodyComposition: PreviewBodyCompositionReader(), medicalProfile: PreviewHealthProfileReader.medicalPreview)

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
