import Foundation
import LingoCore

/// Arma el contexto opcional del análisis (T-33). Puro y determinista: recibe el snapshot **ya compactado**, los
/// eventos del período, la nutrición por `eventID`, las noches, los pasos, el perfil y los interruptores, y devuelve
/// `nil` si todo está apagado o vacío.
///
/// - Comidas: solo las que siguen en el snapshot compactado (unidas por `at`); si `compact()` las quitó, no van.
///   Nombre del registro de nutrición o, sin registro, el texto del evento (60 caracteres, una línea).
/// - Sueño y pasos: las últimas 31 noches y 31 días. Perfil: edad, sexo, altura y la composición corporal (peso,
///   IMC, grasa, masa magra, cintura y su tendencia), con el peso y el IMC de la báscula si existen.
/// - Si el JSON pasa de `maxBytes`, recorta por orden: sueño a 14 noches, comidas a 30, pasos a 14 días.
enum ReportAnalysisContextBuilder {
    static let maxBytes = 20_000
    static let maxNameLength = 60
    static let maxNights = 31
    static let maxStepDays = 31
    static let trimmedNights = 14
    static let trimmedMeals = 30
    static let trimmedStepDays = 14

    static func build(
        snapshot: ReportSnapshot, events: [DiaryEvent], nutrition: [String: MealNutritionRecord],
        sleep: [SleepNight], steps: [DailySteps], profile: HealthProfile?, body: BodyComposition = .empty,
        sharing: ReportAnalysisSharing
    ) -> ReportAnalysisContext? {
        guard !sharing.isEmpty else { return nil }
        var context = ReportAnalysisContext()
        if sharing.meals {
            context.meals = nonEmpty(meals(snapshot: snapshot, events: events, nutrition: nutrition))
        }
        if sharing.sleepActivity {
            context.sleep = nonEmpty(Array(sleep.sorted { $0.night < $1.night }.suffix(maxNights)))
            let days = Array(steps.filter { $0.steps > 0 }.sorted { $0.day < $1.day }.suffix(maxStepDays))
            context.activity = days.isEmpty ? nil : ReportAnalysisActivityContext(dailySteps: days)
        }
        if sharing.profile {
            let summary = Self.profile(profile ?? .empty, body: body)
            context.profile = summary.isEmpty ? nil : summary
        }
        guard !context.isEmpty else { return nil }
        return trimmed(context)
    }

    /// Recorta por tamaño, en el orden del diseño, hasta caber en `maxBytes` (o hasta agotar los recortes).
    static func trimmed(_ context: ReportAnalysisContext, maxBytes: Int = maxBytes) -> ReportAnalysisContext {
        var result = context
        let steps: [(inout ReportAnalysisContext) -> Void] = [
            { $0.sleep = $0.sleep.map { Array($0.suffix(trimmedNights)) } },
            { $0.meals = $0.meals.map { Array($0.suffix(trimmedMeals)) } },
            { context in
                guard var activity = context.activity else { return }
                activity.dailySteps = Array(activity.dailySteps.suffix(trimmedStepDays))
                context.activity = activity
            },
        ]
        for step in steps where result.jsonByteCount > maxBytes {
            step(&result)
        }
        return result
    }

    /// Nombre en una línea, sin espacios repetidos y como mucho `maxNameLength` caracteres; `nil` si queda vacío.
    static func cleanName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let oneLine = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        let cut = String(oneLine.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? nil : cut
    }

    // MARK: - Interno

    private static func meals(snapshot: ReportSnapshot, events: [DiaryEvent],
                              nutrition: [String: MealNutritionRecord]) -> [ReportAnalysisMealContext] {
        var byTime: [UTCInstant: DiaryEvent] = [:]
        for event in events where event.kind == .meal && !event.deleted && byTime[event.at] == nil {
            byTime[event.at] = event
        }
        return snapshot.meals.meals.compactMap { meal -> ReportAnalysisMealContext? in
            guard let event = byTime[meal.at] else { return nil }
            let record = nutrition[event.eventID]
            let nutrients = record?.effectiveNutrients ?? .unknown
            let item = ReportAnalysisMealContext(
                at: meal.at, name: cleanName(record?.name) ?? cleanName(event.text),
                kcal: r1(nutrients.kcal), carbsG: r1(nutrients.carbsG), proteinG: r1(nutrients.proteinG), fatG: r1(nutrients.fatG),
                source: record.map { source($0.source) }, kind: record?.kind.rawValue)
            return item.name == nil && nutrients.isUnknown ? nil : item
        }
    }

    private static func profile(_ profile: HealthProfile, body: BodyComposition) -> ReportAnalysisProfileContext {
        let weight = body.latest[.weight] ?? r1(profile.weightKg)
        var computedBMI: Double?
        if let weight, let height = profile.heightCm, height > 0 {
            computedBMI = weight / ((height / 100) * (height / 100))
        }
        return ReportAnalysisProfileContext(
            ageYears: profile.ageYears, sex: profile.biologicalSex?.rawValue,
            weightKg: weight, heightCm: r1(profile.heightCm), bmi: body.latest[.bmi] ?? r1(computedBMI),
            bodyFatPct: body.latest[.bodyFat], leanMassKg: body.latest[.leanMass], waistCm: body.latest[.waist],
            bodyTrend: body.trends.isEmpty ? nil : body.trends)
    }

    private static func source(_ source: MealNutritionSource) -> String {
        switch source {
        case .llm: "assistant"
        case .label: "label"
        case .manual: "manual"
        }
    }

    private static func nonEmpty<T>(_ items: [T]) -> [T]? { items.isEmpty ? nil : items }

    private static func r1(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return (value * 10).rounded() / 10
    }
}
