import Foundation
import LingoCore
import Testing
@testable import LingoScan

/// Reabrir una comida cuyos carbohidratos cambiaron fuera de la app (T-21). Todo sintético.
@MainActor
struct MealReopenNoticeTests {
    private func savedMeal(_ env: MealTestEnvironment, ids: IDSequence) async throws -> (DiaryEvent, MealNutritionRecord) {
        let model = env.viewModel(ids: ids)
        await model.prepare()
        model.descriptionText = "arepa con queso"
        await model.analyze()
        model.setMultiplier(1.5)   // 300 kcal / 45 g
        #expect(await model.save())
        let event = try #require(await env.store.savedEvents.last)
        let record = try #require(try await env.store.mealNutrition(eventID: event.eventID))
        return (event, record)
    }

    @Test func matchingCarbsShowNoNotice() async throws {
        let env = try await MealTestEnvironment.make()
        let (event, record) = try await savedMeal(env, ids: IDSequence())
        #expect(event.carbsG == 45)
        #expect(MealAnalysisViewModel(reopening: event, record: record, services: env.services).externalChangeNotice == nil)
    }

    @Test func differentCarbsWarnAndNothingIsWrittenUntilSaving() async throws {
        let env = try await MealTestEnvironment.make()
        let ids = IDSequence()
        let (event, record) = try await savedMeal(env, ids: ids)
        var outside = event
        outside.carbsG = 12
        let reopened = MealAnalysisViewModel(reopening: outside, record: record, services: env.services,
                                             calendar: MealTestEnvironment.calendar, now: { MealTestEnvironment.now },
                                             newID: { ids.next() })
        #expect(reopened.externalChangeNotice != nil)
        #expect(reopened.adjusted.carbsG == 45, "la pantalla muestra lo del registro, no el valor externo")
        #expect(!reopened.didSave)
        #expect(await env.store.savedEvents.count == 1)

        #expect(await reopened.save())
        let saved = try #require(await env.store.savedEvents.last)
        #expect(await env.store.savedEvents.count == 2)
        #expect(saved.carbsG == 45, "al guardar manda el registro")
        #expect(saved.parentEditID == outside.editID && saved.revision == outside.revision + 1)
    }

    @Test func eventWithoutCarbsAlsoWarns() async throws {
        let env = try await MealTestEnvironment.make()
        let (event, record) = try await savedMeal(env, ids: IDSequence())
        var outside = event
        outside.carbsG = nil
        let reopened = MealAnalysisViewModel(reopening: outside, record: record, services: env.services)
        #expect(reopened.externalChangeNotice != nil)
    }

    @Test func differenceBelowRoundingToleranceDoesNotWarn() async throws {
        let env = try await MealTestEnvironment.make()
        let (event, record) = try await savedMeal(env, ids: IDSequence())
        var outside = event
        outside.carbsG = 45.04
        #expect(MealAnalysisViewModel(reopening: outside, record: record, services: env.services).externalChangeNotice == nil)
    }
}
