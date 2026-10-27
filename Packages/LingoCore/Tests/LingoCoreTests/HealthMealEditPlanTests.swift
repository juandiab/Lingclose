import Testing
@testable import LingoCore

/// Edición de comidas y pendientes de Health por nutriente (T-21 §5). Todo sintético.
struct HealthMealEditPlanTests {
    private static let nutrients: [HealthSubjectKind] = [.carbs, .energyKcal, .proteinG, .fatG]

    private func ledger(_ id: String, _ kind: HealthSubjectKind, version: Int, at: Int64 = 10) -> HealthLedgerEntry {
        HealthLedgerEntry(attemptID: TestSupport.newID(), subjectID: id, subjectKind: kind, writerAppID: TestSupport.appID,
                          syncIdentifier: HealthNutrientExportable.syncIdentifier(eventID: id, kind: kind),
                          syncVersion: version, exportedAt: UTCInstant(epochSeconds: at), result: .written)
    }

    private func edit(of event: DiaryEvent, editID: String) -> DiaryEvent {
        var next = event
        next.editID = editID
        next.parentEditID = event.editID
        next.revision = event.revision + 1
        next.updatedAt = event.updatedAt.adding(seconds: 600)
        return next
    }

    private func full(_ id: String, multiplier: Double = 1.0) -> MealNutritionRecord {
        MealNutritionStoreTests.nutrition(id, multiplier: multiplier, overrides: .unknown,
                                          base: Nutrients(kcal: 200, carbsG: 30, proteinG: 10, fatG: 5))
    }

    @Test func editingMealWithNewMultiplierLeavesAllFourPendingAtNewRevision() async throws {
        let store = try TestSupport.makeStore()
        let id = TestSupport.newID()
        let first = MealNutritionStoreTests.meal(id)
        try await store.saveMeal(event: first, nutrition: full(id))
        for kind in Self.nutrients { try await store.appendLedger(ledger(id, kind, version: first.revision)) }
        #expect(try await store.pendingHealthSubjects().isEmpty, "todo escrito en la revisión 1")

        let second = edit(of: first, editID: TestSupport.newID())
        #expect(try await store.saveMeal(event: second, nutrition: full(id, multiplier: 2.0)) == .tookDescendant)
        let pending = try await store.pendingHealthSubjects()
        #expect(Set(pending.map(\.subjectKind)) == Set(Self.nutrients))
        #expect(pending.count == 4 && Set(pending.map(\.subjectID)) == [id])
        #expect(pending.allSatisfy { $0.revision == second.revision && $0.revision == 2 })

        let stored = try #require(try await store.event(id: id))
        let specs = HealthSampleMapper.specs(for: stored, nutrition: try await store.mealNutrition(eventID: id))
        #expect(specs.map(\.kind) == [.carbs, .energyKcal, .proteinG, .fatG])
        #expect(specs.map(\.value) == [60, 400, 20, 10], "valores desde la base × 2,0")
        #expect(specs.allSatisfy { $0.syncVersion == 2 })
        #expect(specs.map(\.syncIdentifier) == [id, "\(id):energy_kcal", "\(id):protein_g", "\(id):fat_g"],
                "mismo sync_identifier que en la revisión 1: Health sustituye la muestra")
    }

    @Test func nutrientTurnedUnknownProducesNoSubject() async throws {
        let store = try TestSupport.makeStore()
        let id = TestSupport.newID()
        let first = MealNutritionStoreTests.meal(id)
        try await store.saveMeal(event: first, nutrition: full(id))

        let second = edit(of: first, editID: TestSupport.newID())
        let withoutProtein = MealNutritionStoreTests.nutrition(id, multiplier: 1.0, overrides: .unknown,
                                                               base: Nutrients(kcal: 200, carbsG: 30, proteinG: nil, fatG: 5))
        try await store.saveMeal(event: second, nutrition: withoutProtein)
        let pending = try await store.pendingHealthSubjects()
        #expect(pending.map(\.subjectKind) == [.carbs, .energyKcal, .fatG])
        #expect(!pending.contains { $0.subjectKind == .proteinG })
        let stored = try #require(try await store.event(id: id))
        #expect(HealthNutrientExportable(event: stored, nutrition: withoutProtein, kind: .proteinG) == nil)
        #expect(HealthSampleMapper.specs(for: stored, nutrition: withoutProtein).map(\.kind) == [.carbs, .energyKcal, .fatG])
    }

    @Test func writtenEnergyDoesNotHideAPendingCarb() async throws {
        let store = try TestSupport.makeStore()
        let id = TestSupport.newID()
        let meal = MealNutritionStoreTests.meal(id)
        try await store.saveMeal(event: meal, nutrition: full(id))
        try await store.appendLedger(ledger(id, .energyKcal, version: meal.revision))
        let pending = try await store.pendingHealthSubjects()
        #expect(pending.map(\.subjectKind) == [.carbs, .proteinG, .fatG])
        #expect(!pending.contains { $0.subjectKind == .energyKcal })
    }
}
