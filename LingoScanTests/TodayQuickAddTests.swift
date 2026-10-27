import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// Registro rápido de Hoy: guarda por `DiaryStore` con linaje (T-11b).
@MainActor
struct TodayQuickAddTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(store: InMemoryDiaryStore, ids: IDSequence = IDSequence()) -> QuickAddModel {
        QuickAddModel(store: store, at: Self.now, now: { Self.now }, newID: { ids.next() })
    }

    @Test func mealSavesWithLineageInTwoSteps() async throws {
        let store = InMemoryDiaryStore()
        let model = makeModel(store: store)
        #expect(!model.canSave)
        model.choose(.meal)                      // toque 1
        #expect(model.canSave)
        #expect(await model.save())              // toque 2
        let all = await store.history
        let event = try #require(all.first)
        #expect(all.count == 1)
        #expect(event.kind == .meal)
        #expect(event.at.date == Self.now)
        #expect(event.revision == 1)
        #expect(event.parentEditID == nil)
        #expect(!event.editID.isEmpty)
        #expect(event.editedByAppID == DiaryViewModel.appID)
        #expect(!event.deleted && !event.synthetic)
    }

    @Test func exerciseNeedsDurationAndSuggestsThirtyMinutes() async throws {
        let store = InMemoryDiaryStore()
        let model = makeModel(store: store)
        model.choose(.exercise)
        #expect(model.draft.durationText == "30")
        #expect(model.canSave)
        model.draft.durationText = ""
        #expect(!model.canSave)
        model.draft.durationText = "45"
        #expect(await model.save())
        #expect(await store.history.first?.durationMin == 45)
    }

    @Test func noteNeedsText() async throws {
        let store = InMemoryDiaryStore()
        let model = makeModel(store: store)
        model.choose(.note)
        #expect(!model.canSave)
        model.draft.text = "  Caminata corta  "
        #expect(await model.save())
        #expect(await store.history.first?.text == "Caminata corta")
    }

    @Test func savedEventAppearsAsAMarkOnTheCurve() async throws {
        let data = PreviewData(now: Self.now)
        let model = TodayViewModel(dataSource: data, sensorSource: data, clock: { Self.now })
        await model.refresh()
        let before = model.marks.count
        let quick = QuickAddModel(store: model.diaryStore, at: Self.now.addingTimeInterval(-30 * 60), now: { Self.now })
        quick.choose(.meal)
        quick.draft.carbsText = "30"
        #expect(await quick.save())
        await model.refresh()
        #expect(model.marks.count == before + 1)
        #expect(model.marks.contains { $0.kind == .meal && $0.date == Self.now.addingTimeInterval(-30 * 60) })
    }

    @Test func failedSaveKeepsTheSheetOpenState() async {
        let store = InMemoryDiaryStore()
        await store.setFailNextSave(true)
        let model = makeModel(store: store)
        model.choose(.meal)
        #expect(!(await model.save()))
        #expect(model.didFailToSave)
        #expect(await store.history.isEmpty)
    }
}
