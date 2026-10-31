import Foundation
import LingoCore
@testable import LingoScan

/// Datos inventados del contexto opcional (T-33): comidas, noches, pasos y composición corporal. Nada real.
enum ReportAnalysisContextFixtures {
    static let mealName = "Arroz con pollo y ensalada"

    static func record(for event: DiaryEvent, name: String? = mealName, assumptions: String? = "SUPUESTO-INVENTADO",
                       source: MealNutritionSource = .llm(provider: "anthropic", model: "modelo-inventado"),
                       kind: FoodAnalysisKind = .food) -> MealNutritionRecord {
        MealNutritionRecord(
            eventID: event.eventID, source: source, kind: kind, name: name,
            basis: .estimatedServing(description: "1 plato", grams: 350),
            baseNutrients: Nutrients(kcal: 642.26, carbsG: 80.04, proteinG: 31.96, fatG: 17.51),
            assumptions: assumptions, confidence: 0.8, updatedAt: event.at)
    }

    static func night(_ day: Int) -> SleepNight {
        let date = String(format: "2026-09-%02d", day % 30 + 1)
        let bed = UTCInstant(epochSeconds: 1_790_000_000 + Int64(day) * 86_400)
        return SleepNight(night: date, bedAt: bed, wakeAt: bed.adding(seconds: 8 * 3_600), inBedMin: 480, asleepMin: 440,
                          awakeMin: 20, deepMin: 70, remMin: 90, coreMin: 280, awakenings: 2)
    }

    static func nights(_ count: Int) -> [SleepNight] {
        (0..<count).map { i in
            var n = night(i)
            n.night = "2026-" + String(format: "%02d-%02d", 7 + i / 28, i % 28 + 1)
            return n
        }
    }

    static func steps(_ count: Int) -> [DailySteps] {
        (0..<count).map { i in DailySteps(day: "2026-" + String(format: "%02d-%02d", 7 + i / 28, i % 28 + 1), steps: 5_000 + i) }
    }

    static let profile = HealthProfile(ageYears: 40, biologicalSex: .male, weightKg: 70.04, heightCm: 175)

    static func body(timeZone: TimeZone = ReportAnalysisFixtures.bogota) -> BodyComposition {
        let start = Date(timeIntervalSince1970: 1_799_500_000)
        let end = start.addingTimeInterval(5 * 86_400)
        return BodyComposition.make(
            latest: [.weight: BodyMeasurement(date: end, value: 69.46), .bodyFat: BodyMeasurement(date: end, value: 21.34),
                     .leanMass: BodyMeasurement(date: end, value: 54.61), .bmi: BodyMeasurement(date: end, value: 22.71),
                     .waist: BodyMeasurement(date: end, value: 81.96)],
            inPeriod: [.weight: [BodyMeasurement(date: start, value: 70.66), BodyMeasurement(date: end, value: 69.46)],
                       .bodyFat: [BodyMeasurement(date: start, value: 22.0), BodyMeasurement(date: end, value: 21.34)],
                       // Una sola muestra de masa magra: sin tendencia.
                       .leanMass: [BodyMeasurement(date: end, value: 54.61)]],
            timeZone: timeZone)
    }
}
