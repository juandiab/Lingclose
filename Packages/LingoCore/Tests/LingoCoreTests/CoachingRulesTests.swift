import Foundation
import Testing
@testable import LingoCore

/// Consejos por reglas (T-25): cobertura por tipo, límite, determinismo y textos sin fármacos.
struct CoachingRulesTests {
    /// Contextos variados por tipo: con y sin comida, ejercicio, noche, pendiente y tiempo en rango.
    static func contexts(for kind: AlertKind) -> [CoachingContext] {
        let value: Int? = switch kind {
        case .high, .risingFast: 165
        case .low, .fallingFast: 62
        case .noData: nil
        }
        var list: [CoachingContext] = []
        for hour in [2, 8, 14, 23] {
            for meal in [nil, 20, 100, 300] as [Int?] {
                for exercise in [nil, 30, 200] as [Int?] {
                    for slope in [nil, -2.5, 0.4, 2.6] as [Double?] {
                        list.append(CoachingContext(
                            kind: kind, value: value, slopePerMinute: slope, minutesSinceLastMeal: meal,
                            lastMealCarbsG: meal == nil ? nil : 60, minutesSinceLastExercise: exercise, hour: hour,
                            timeInRangeToday: hour == 14 ? 0.3 : 0.9))
                    }
                }
            }
        }
        return list
    }

    @Test(arguments: AlertKind.allCases)
    func everyKindGetsAtLeastOneTipAndNeverMoreThanTheLimit(kind: AlertKind) {
        for context in Self.contexts(for: kind) {
            for limit in 1...3 {
                let tips = CoachingRules.tips(for: context, limit: limit)
                #expect(!tips.isEmpty, "\(kind) sin consejos en \(context)")
                #expect(tips.count <= limit)
                #expect(Set(tips.map(\.id)).count == tips.count, "sin repetidos")
            }
            #expect(CoachingRules.tips(for: context).count <= 2, "límite por defecto 2")
            #expect(CoachingRules.tips(for: context, limit: 0).isEmpty)
        }
    }

    @Test(arguments: AlertKind.allCases)
    func isDeterministic(kind: AlertKind) {
        for context in Self.contexts(for: kind) {
            let first = CoachingRules.tips(for: context, limit: 3)
            for _ in 0..<5 { #expect(CoachingRules.tips(for: context, limit: 3) == first) }
        }
    }

    @Test func catalogHasSensibleSizeUniqueIDsAndShortSentences() {
        let all = CoachingCatalog.all
        #expect((12...16).contains(all.count))
        #expect(Set(all.map(\.id)).count == all.count)
        for tip in all {
            #expect(!tip.title.isEmpty)
            #expect(tip.body.count <= CoachingTip.maxBodyLength, "\(tip.id): \(tip.body.count) caracteres")
            #expect(tip.titleKey == "coaching.\(tip.id).title")
            #expect(tip.bodyKey == "coaching.\(tip.id).body")
            #expect(CoachingRules.tip(id: tip.id) == tip)
        }
    }

    @Test func noTipTalksAboutInsulinOrMedication() {
        for tip in CoachingCatalog.all {
            let text = (tip.title + " " + tip.body).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            for banned in ["insulina", "insulin", "medic", "farmaco", "dosis", "pastilla"] {
                #expect(!text.contains(banned), "\(tip.id) contiene \(banned)")
            }
        }
    }

    @Test func everyCatalogTipIsReachable() {
        var reached = Set<String>()
        for kind in AlertKind.allCases {
            for context in Self.contexts(for: kind) {
                reached.formUnion(CoachingRules.tips(for: context, limit: 5).map(\.id))
            }
        }
        #expect(reached == Set(CoachingCatalog.all.map(\.id)))
    }

    // MARK: - Ejemplos del encargo

    @Test func highAfterRecentMealSuggestsWalkingThenWater() {
        let context = CoachingContext(kind: .high, value: 165, slopePerMinute: 1.2, minutesSinceLastMeal: 40,
                                      lastMealCarbsG: 30, hour: 14)
        #expect(CoachingRules.tips(for: context).map(\.id) == ["walkAfterMeal", "waterNoSugar"])
        #expect(CoachingRules.tips(for: context).first?.body == "Caminar 10–15 min ayuda a suavizar el pico.")
    }

    @Test func risingFastAfterMealAtNightAvoidsWalking() {
        let context = CoachingContext(kind: .risingFast, value: 150, slopePerMinute: 2.5, minutesSinceLastMeal: 30, hour: 23)
        #expect(CoachingRules.tips(for: context).map(\.id) == ["waterNoSugar", "risingWait"])
    }

    @Test func largeMealAddsTheNextMealIdea() {
        let context = CoachingContext(kind: .high, value: 180, minutesSinceLastMeal: 50, lastMealCarbsG: 90, hour: 13)
        #expect(CoachingRules.tips(for: context, limit: 3).map(\.id) == ["walkAfterMeal", "waterNoSugar", "mealOrder"])
    }

    @Test func highWithoutMealAsksAboutContext() {
        let day = CoachingContext(kind: .high, value: 150, hour: 10)
        #expect(CoachingRules.tips(for: day).map(\.id) == ["noteContext", "moveLight"])
        let night = CoachingContext(kind: .high, value: 150, hour: 3)
        #expect(CoachingRules.tips(for: night).map(\.id) == ["noteContext", "restBreath"])
        let oldMeal = CoachingContext(kind: .high, value: 150, minutesSinceLastMeal: 240, hour: 10)
        #expect(CoachingRules.tips(for: oldMeal).first?.id == "noteContext")
    }

    @Test func highAlreadyFallingSaysToWait() {
        let context = CoachingContext(kind: .high, value: 150, slopePerMinute: -1.5, minutesSinceLastMeal: 60, hour: 15)
        #expect(CoachingRules.tips(for: context).map(\.id) == ["alreadyFalling", "walkAfterMeal"])
    }

    @Test func lowTimeInRangeSuggestsAProfessionalOnlyAfterTheMainTips() {
        let context = CoachingContext(kind: .high, value: 190, hour: 10, timeInRangeToday: 0.3)
        #expect(CoachingRules.tips(for: context, limit: 4).map(\.id) == ["noteContext", "moveLight", "risingWait", "highPersisting"])
    }

    @Test func lowPutsSymptomsFirstThenCompression() {
        let context = CoachingContext(kind: .low, value: 62, hour: 3)
        #expect(CoachingRules.tips(for: context).map(\.id) == ["lowSymptoms", "lowCompression"])
        let afterGym = CoachingContext(kind: .low, value: 64, minutesSinceLastExercise: 20, hour: 18)
        #expect(CoachingRules.tips(for: afterGym).map(\.id) == ["lowSymptoms", "afterExercise"])
    }

    @Test func fallingFastAfterExerciseIsNormal() {
        let context = CoachingContext(kind: .fallingFast, value: 85, slopePerMinute: -2.4, minutesSinceLastExercise: 10, hour: 18)
        #expect(CoachingRules.tips(for: context).first?.id == "afterExercise")
        let night = CoachingContext(kind: .fallingFast, value: 80, slopePerMinute: -2.4, hour: 2)
        #expect(CoachingRules.tips(for: night).first?.id == "lowCompression")
        let plain = CoachingContext(kind: .fallingFast, value: 80, slopePerMinute: -2.4, hour: 11)
        #expect(CoachingRules.tips(for: plain).map(\.id) == ["fallingWatch", "fallingSnack"])
    }

    @Test func noDataPointsToBluetoothAndThePhone() {
        let context = CoachingContext(kind: .noData, hour: 12)
        #expect(CoachingRules.tips(for: context).map(\.id) == ["noDataBluetooth", "noDataPhone"])
    }

    @Test func contextFlagsAndCoding() throws {
        let context = CoachingContext(kind: .risingFast, value: 140, slopePerMinute: 2.1, minutesSinceLastMeal: 120,
                                      lastMealCarbsG: 40, minutesSinceLastExercise: 91, hour: 30, timeInRangeToday: 0.8)
        #expect(context.hour == 23)
        #expect(context.isNight)
        #expect(context.hasRecentMeal)
        #expect(!context.hasRecentExercise)
        let decoded = try JSONDecoder().decode(CoachingContext.self, from: JSONEncoder().encode(context))
        #expect(decoded == context)
    }
}
