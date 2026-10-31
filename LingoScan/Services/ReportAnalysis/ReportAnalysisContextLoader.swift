import Foundation
import LingoCore

/// Reúne lo que el contexto opcional necesita (T-33): la nutrición de las comidas del snapshot y, solo si el
/// interruptor está encendido, el sueño, los pasos, el perfil y la composición corporal de Apple Salud. Nunca falla: lo que no se puede leer
/// queda vacío y el análisis sigue sin ese bloque. No pide permisos (eso lo hace el interruptor al encenderse).
struct ReportAnalysisContextLoader: Sendable {
    let nutrition: any MealNutritionStore
    let health: ReportAnalysisHealthSources

    /// Lo que se usa si no se inyecta otra cosa: sin nutrición guardada y Salud sintética.
    static let unavailable = ReportAnalysisContextLoader(nutrition: InMemoryMealNutritionStore(), health: .preview)

    /// Previsualización: nombres de comida y datos de Salud inventados.
    static let preview = ReportAnalysisContextLoader(nutrition: PreviewMealNutritionStore(), health: .preview)

    func load(snapshot: ReportSnapshot, events: [DiaryEvent], period: ReportPeriod,
              sharing: ReportAnalysisSharing) async -> ReportAnalysisContext? {
        guard !sharing.isEmpty else { return nil }
        var records: [String: MealNutritionRecord] = [:]
        if sharing.meals {
            let times = Set(snapshot.meals.meals.map(\.at))
            for event in events where event.kind == .meal && !event.deleted && times.contains(event.at) {
                if let record = try? await nutrition.mealNutrition(eventID: event.eventID) {
                    records[event.eventID] = record
                }
            }
        }
        var nights: [SleepNight] = []
        var steps: [DailySteps] = []
        if sharing.sleepActivity {
            let timeZone = period.timeZone
            // Desde las 12:00 del día anterior al primero: la noche que empieza el día previo (como `NightReport`).
            let from = period.start.date.addingTimeInterval(-12 * 3_600)
            nights = await health.sleepActivity.sleepNights(from: from, to: period.end.date, timeZone: timeZone)
            steps = await health.sleepActivity.dailySteps(from: period.start.date, to: period.end.date, timeZone: timeZone)
        }
        var profile: HealthProfile?
        var body = BodyComposition.empty
        if sharing.profile {
            profile = try? await health.profile.readProfile()
            body = await health.bodyComposition.bodyComposition(from: period.start.date, to: period.end.date,
                                                                timeZone: period.timeZone)
        }
        return ReportAnalysisContextBuilder.build(
            snapshot: snapshot, events: events, nutrition: records, sleep: nights, steps: steps,
            profile: profile, body: body, sharing: sharing)
    }
}
