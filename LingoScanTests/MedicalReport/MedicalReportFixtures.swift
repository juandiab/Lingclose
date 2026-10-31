import Foundation
import LingoCore
@testable import LingoScan

/// Datos inventados del reporte para el médico (T-34): 14 días de lecturas cada minuto con comidas, subidas altas,
/// bajadas nocturnas, ejercicio y notas. Nada real: nombres, textos y cifras son de prueba.
enum MedicalReportFixtures {
    static let bogota = TimeZone(identifier: "America/Bogota")!
    static let end = UTCInstant(epochSeconds: 1_800_000_000)
    static let testName = "Paciente Prueba Zeta"
    static let locale = Locale(identifier: "es_CO")

    private static let mealNames = ["Arepa con huevo y queso", "Arroz con pollo y ensalada", "Sopa de lentejas con arroz",
                                    "Avena con banano", "Pasta con tomate", "Sándwich de pavo"]
    private static let noteTexts = ["Estrés laboral por la tarde", "Cena tarde por reunión", "Dormí mal, poco descanso",
                                    "Caminata larga el fin de semana"]

    static func period(days: Int = 14) -> ReportPeriod { .last(days, endingAt: end, timeZone: bogota) }

    /// Glucosa simulada del minuto `minute` desde el inicio del período `from`.
    private static func value(at epoch: Int64, meals: [Int64], lows: [Int64]) -> Int {
        let minuteOfDay = Double((epoch / 60 - 5 * 60) % 1_440)
        var v = 104 + 12 * sin(minuteOfDay / 1_440 * 2 * .pi + 0.4)
        for (index, meal) in meals.enumerated() where epoch >= meal && epoch < meal + 18_000 {
            let x = Double(epoch - meal) / 60 / 50
            let amplitude = 36 + Double((index * 37) % 95)
            v += amplitude * x * exp(1 - x)
        }
        for low in lows {
            let d = Double(epoch - low) / 60 / 40
            v -= 48 * exp(-d * d)
        }
        v += 3 * sin(Double(epoch / 60) * 0.7)
        return min(max(Int(v.rounded()), 48), 295)
    }

    static func bundleWithEvents(days: Int = 14, configuration: ReportConfiguration = .default,
                                 withDiary: Bool = true) -> (bundle: ReportBundle, events: [DiaryEvent]) {
        let period = period(days: days)
        var events: [DiaryEvent] = []
        var mealTimes: [Int64] = []
        var lows: [Int64] = []
        for day in 0..<days {
            let midnight = period.start.epochSeconds + Int64(day) * 86_400
            if withDiary {
                for (slot, hour) in [8, 13, 19].enumerated() {
                    let at = UTCInstant(epochSeconds: midnight + Int64(hour) * 3_600 + Int64(slot) * 600)
                    mealTimes.append(at.epochSeconds)
                    events.append(event(.meal, at: at, carbs: Double(35 + (day * 7 + slot * 19) % 60),
                                        text: mealNames[(day + slot) % mealNames.count]))
                }
                if day % 3 == 1 {
                    events.append(event(.exercise, at: UTCInstant(epochSeconds: midnight + 17 * 3_600 + 1_800),
                                        duration: 30 + (day % 4) * 5, text: day % 2 == 0 ? "Caminata" : "Bicicleta estática"))
                }
                if day % 4 == 2 {
                    events.append(event(.note, at: UTCInstant(epochSeconds: midnight + 20 * 3_600), text: noteTexts[day % noteTexts.count]))
                }
            }
            if day % 5 == 3 { lows.append(midnight + 8 * 3_600) }
        }
        // Las lecturas empiezan antes del período (semana anterior y líneas base).
        let from = period.dataStart.epochSeconds
        let allMeals = mealTimes
        let samples = stride(from: from, to: end.epochSeconds, by: 60).map { t in
            BasicStats.Sample(measuredAt: UTCInstant(epochSeconds: t), valueMgdl: value(at: t, meals: allMeals, lows: lows))
        }
        return (ReportBuilder.build(samples: samples, events: events, period: period, configuration: configuration), events)
    }

    static func event(_ kind: DiaryEventKind, at: UTCInstant, carbs: Double? = nil, duration: Int? = nil,
                      text: String?) -> DiaryEvent {
        DiaryEvent(eventID: "t34-\(kind.rawValue)-\(at.epochSeconds)", kind: kind, at: at, tz: "America/Bogota",
                   durationMin: duration, carbsG: carbs, text: text, createdAt: at, updatedAt: at,
                   editID: "edit-\(at.epochSeconds)", editedByAppID: "test-app", synthetic: true)
    }

    /// Nutrición inventada para cada comida (nombre y nutrientes).
    static func nutrition(for events: [DiaryEvent]) -> [String: MealNutritionRecord] {
        var result: [String: MealNutritionRecord] = [:]
        for event in events where event.kind == .meal {
            result[event.eventID] = MealNutritionRecord(
                eventID: event.eventID, source: .manual, kind: .food, name: event.text,
                basis: .estimatedServing(description: nil, grams: nil),
                baseNutrients: Nutrients(kcal: 540, carbsG: event.carbsG, proteinG: 24.5, fatG: 17),
                updatedAt: event.at)
        }
        return result
    }

    /// Entrada completa con Salud sintética (perfil, composición corporal, sueño y pasos).
    static func input(days: Int = 14, options: MedicalReportOptions = .all, name: String = testName,
                      configuration: ReportConfiguration = .default, unit: MedicalGlucoseUnit = .mgdl,
                      isSynthetic: Bool = true, withHealth: Bool = true, withDiary: Bool = true) async -> MedicalReportInput {
        let (bundle, events) = bundleWithEvents(days: days, configuration: configuration, withDiary: withDiary)
        let period = bundle.period
        var input = MedicalReportInput(
            bundle: bundle, events: events, nutrition: nutrition(for: events), options: options, patientName: name,
            isSynthetic: isSynthetic, generatedAt: Date(timeIntervalSince1970: 1_800_000_000), unit: unit, locale: locale)
        guard withHealth else { return input }
        input.profile = PreviewHealthProfileReader.medicalPreview.profile
        let body = PreviewBodyCompositionReader()
        input.body = await body.bodyComposition(from: period.start.date, to: period.end.date, timeZone: period.timeZone)
        input.bodySeries = await body.bodyMeasurementSeries(from: period.start.date, to: period.end.date)
        let sleep = PreviewSleepActivityReader()
        input.sleep = await sleep.sleepNights(from: period.start.date.addingTimeInterval(-12 * 3_600), to: period.end.date,
                                              timeZone: period.timeZone)
        input.steps = await sleep.dailySteps(from: period.start.date, to: period.end.date, timeZone: period.timeZone)
        return input
    }
}
